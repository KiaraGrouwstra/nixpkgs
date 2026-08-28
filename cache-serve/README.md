# nix-cache-serve

A read-only per-file endpoint in front of a Nix binary cache:

```
GET /serve/<storehash>/<path-within-store-path>
```

returns that one file's bytes. This is the proof of concept for the proposal in
`../ISSUE-infra-per-file.md`, and it exists to produce the one number that
proposal admits it cannot estimate from outside: what moving decompression to
the serving side costs.

Nothing is signed, no store semantics are involved and there is no write path.
This is the same trust level as the `.ls` listing it complements, which is
already public and already consumed by third-party tooling.

## Why this exists

Tools that want to *read* from the binary cache rather than *install* from it
have to download whole NARs today. For a desktop-entry indexer over the
`nixos-25.05` channel that is 3.148 GiB of transfer for 15.95 MiB of payload, a
202x amplification. The client-side alternative -- range-fetching the NAR prefix
up to `narOffset` -- saves only 20.1%, because NAR entries are sorted and
`share/` sorts near the end.

## How a request works

1. Fetch `<storehash>.narinfo` from the upstream cache to find the NAR and its
   compression.
2. Stream the NAR, decompressing forward.
3. Walk the archive to the wanted path. Directory entries are sorted, so at each
   level the scan either descends, skips an entry that sorts earlier, or
   concludes the path is absent because it has passed where the name would be.
4. Stop at the first content byte -- which is exactly what a `.ls` listing calls
   `narOffset` -- stream out that file's bytes, and drop the upstream connection.

The last step matters: the archive is only decompressed as far as the wanted
file, not to the end.

This deliberately does not use `narOffset` from the `.ls` listing. Published
NARs are single-frame zstd, so knowing the offset would not let anything seek to
it; the prefix has to be decompressed either way. Parsing the archive directly
also means the endpoint works regardless of whether listings carry offsets,
which they currently do not.

Symlinks are answered with `303 See Other` rather than followed, because
following one would mean a second pass over the archive, or a different archive
entirely. A redirect makes that the client's next request, which the CDN in
front can cache like any other. Targets that leave the store are a 404.
Directories are a 404 pointing at `.ls`, which is the existing way to enumerate
a store path.

## What it costs

Measured against `https://cache.nixos.org` over 24 store paths from the local
`nixos-unstable` closure that contain a desktop entry. Raw data in
`measurements/desktop-entries.tsv`, reproduced with `scripts/measure.sh`.

| | |
| --- | --- |
| bytes delivered to the client | 50,241 |
| compressed NAR bytes those files live in | 305,513,779 |
| client-side saving | **6,080x** |
| compressed bytes actually fetched from upstream | 222,934,055 (73%) |
| uncompressed bytes the server had to decode | 973,574,817 of 1,348,801,624 (**72%**) |
| per-request wall time | median 0.36s, p90 1.71s, max 6.45s |

Read that as three separate findings.

**The client-side win is real and large.** 6,080x fewer bytes for this workload,
against the 202x that whole-NAR fetching costs today.

**The server-side cost is real too, and it is most of the archive.** A median
request decompresses 86.6% of its NAR; the byte-weighted mean is 72%. Stopping
early saves about a quarter of the work, which is the same order as the 20.1%
that the purely client-side option D would have saved. The endpoint's value is
not that it avoids decompression -- it is that the decompression happens once,
on a machine with the archive already nearby, instead of at every client.

**The tail is long.** 6.45s of CPU for one request against a 700 MB NAR. That is
why the service caps concurrent decompressions (`--max-concurrency`, default one
per core) and why the Fastly backend below is given a 60s `first_byte_timeout`.
It is also the strongest argument against running this on Fastly Compute: a
Wasm runtime with a per-request CPU budget is the wrong shape for a workload
whose tail is seconds of pure decompression. An ordinary HTTPS origin behind the
existing shield is not.

## Running it

```console
$ nix-shell --run 'cargo run -- --listen 127.0.0.1:8088'
$ curl http://127.0.0.1:8088/serve/990fkc8a2nqgks20zhvb8grm9yd8158f/share/applications/vlc.desktop
```

Options: `--listen`, `--upstream` (default `https://cache.nixos.org`) and
`--max-concurrency`. Each also reads from `NIX_CACHE_SERVE_*` in the
environment. `/metrics` serves Prometheus text and `/health` a liveness probe.

`module.nix` is a NixOS module (`services.nix-cache-serve.enable`) running it
under `DynamicUser` with no access to the host beyond outbound TCP.

## Fastly integration

`terraform/cache.tf.patch` applies to `terraform/cache.tf` in
<https://github.com/NixOS/infra>. It adds one backend and one routing snippet,
and narrows one existing snippet.

`cache.nixos.org` is a `fastly_service_vcl`, so this is a routing change rather
than a rewrite: a VCL service can send a path prefix to a second backend while
everything else keeps its current path. The file already conditions behaviour on
a path prefix in exactly this way, for segmented caching:

```vcl
if (req.url.path ~ "^/nar/") {
  set req.enable_segmented_caching = true;
}
```

The patch adds the same shape for routing:

```vcl
if (req.url.path ~ "^/serve/") {
  set req.backend = F_serve;
}
```

so `/nar/`, `<hash>.narinfo` and `<hash>.ls` continue to be served from S3 with
byte-identical behaviour, and a rollback is deleting one backend block and one
snippet. `/serve/` returns 404 on `cache.nixos.org` today, so nothing collides.

The one existing snippet that has to change is `Authenticate S3 requests`. It
runs on every miss and signs the request with the cache's IAM credentials; the
patch guards it so only S3-bound requests are signed.

Two properties of the surrounding config are worth knowing before deploying it:

- Segmented caching on `/nar/` means the edge already stores NARs in blocks, so
  the origin's forward read pulls only the blocks it reaches rather than the
  whole object.
- The `404-page` response object replaces the body of every 404, so this
  service's explanatory 404 text is not what a client behind Fastly sees. The
  status code is unchanged.

The origin fetches over the public `https://cache.nixos.org` interface, so it
needs no credentials and no bucket access. That does mean a request re-enters
Fastly for the NAR; pointing `--upstream` at the bucket directly would avoid the
hop but requires credentials, because the bucket is requester-pays.

`cache-staging.nixos.org` already exists and is Terraform-managed the same way,
which makes it the natural place to try this before touching production.

## Layout

| | |
| --- | --- |
| `src/nar.rs` | forward-only streaming NAR parser |
| `src/narinfo.rs` | the `.narinfo` fields this needs |
| `src/serve.rs` | the `/serve/` handler |
| `src/metrics.rs` | Prometheus counters |
| `scripts/measure.sh` | drives a running instance and reports per-request cost |
| `terraform/cache.tf.patch` | the Fastly change against `NixOS/infra` |

## Tests

```console
$ nix-shell --run 'cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings && cargo test'
```

The unit tests cover the parser against a synthetic archive, including that a
hit stops exactly at the file's first content byte and that a miss gives up
without reading to the end. They need no network. `scripts/measure.sh` is the
end-to-end check and does need one.
