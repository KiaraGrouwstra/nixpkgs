# Issue draft -- NixOS/infra

**Title:** Serving individual files from `cache.nixos.org`

---

## The ask

A read-only per-file endpoint on `cache.nixos.org`, roughly:

```
GET /serve/<storehash>/<path-within-store-path>
```

returning that one file's bytes. No signature, no store semantics, no write path -- the
same trust level as `.ls`, which is already public and already consumed by third-party
tooling.

I measured the alternatives before asking, and then built the thing so that the cost to
infra is a measurement rather than a guess. The numbers for both are below. What I am
asking for is a decision on whether this is wanted at all -- the implementation is offered,
not assumed.

## The problem

Tools that want to *read* from the binary cache rather than *install* from it have to
download whole NARs. `nix-index`, `command-not-found`, license and security scanners
looking for one `lib*.so`, and the desktop-entry indexer that prompted this all have the
same shape: fetch a large archive, extract a few KB, discard the rest.

For the desktop-entry case I measured it. Random sample of 8,000 of the 205,358 store
paths in the `nixos-25.05` channel closure; 264 of them contain at least one
`share/applications/*.desktop`. The wanted payload is those `.desktop` files plus icons
under `share/icons/` and `share/pixmaps/` in the same path.

| | |
| --- | --- |
| whole-NAR transfer today | **3.148 GiB** |
| wanted payload | **15.95 MiB** |
| amplification | **202x** |

Extrapolated to the channel: roughly 6,800 paths, ~81 GiB of transfer for ~410 MiB of
payload.

The cost is very concentrated, which matters for the design:

| | |
| --- | --- |
| 50% of transfer | top 5 packages (2%) |
| 90% of transfer | top 55 packages (21%) |
| packages > 50 MB compressed | 11 (4.2%) = **64% of transfer**, at **11,333x** |

The pathology is "large package, one small `.desktop`, no icons": `zap-2.16.1` is
1,724,620x. At the other end, icon-heavy packages like `diodon` are 0.17x -- the payload
*is* most of the package, and a client should keep fetching those whole. Any consumer of
this endpoint should be size-thresholded rather than using it for everything.

## Why the cheaper options do not work

I would rather not ask for infrastructure if a client-side trick suffices, so I measured
the client-side trick first.

**D. Prefix-range decode -- the zero-ask baseline, and it does not clear the bar.** Given
`narOffset` from the `.ls` listing, fetch `0..narOffset` with an HTTP `Range` request and
stream-decompress, discarding the prefix. This needs nothing from infra at all. But NAR
entries are sorted, and `share/` sorts near the end, which is exactly where this payload
lives:

| | |
| --- | --- |
| prefix bytes to `maxOffset` | 79.9% of the NAR |
| per-package prefix fraction | median **94.1%**, p90 100.0% |
| saving | **20.1%** |

20% is not worth building a range-decoding client for. And it is currently not even
available: published listings have carried no `narOffset` since the new queue runner was
deployed on 2026-06-17, which I am reporting separately against Hydra. That regression is
worth fixing on its own merits, but fixing it does not make option D worth building.

**A. Uncompressed NARs plus offsets.** Works today with `Range` and needs no new code, at
roughly 3.5x storage and bandwidth cache-wide. Non-starter as a default.

**B. Seekable zstd.** Multiple frames plus a seek table in a skippable frame; backward
compatible, since ordinary decoders ignore skippable frames. Two problems. Published NARs
today are **single-frame** -- verified with `zstd -l` on six NARs including five built in
Aug 2026 with `NarSize` of 25-30 MB, all `frames=1 skips=0` -- so this is a
recompress-the-world change if it is to apply to existing paths, and otherwise only ever
helps newly uploaded ones. It also still needs someone to write the seek-table-aware
client. Nix merged per-16-MiB multi-frame emission in
<https://github.com/NixOS/nix/pull/15550>, but Hydra compresses with its own code and that
is not reflected in what is uploaded.

**E. Out-of-band side artifacts** -- a per-path bundle for one class of files. Cheap to
agree on if the ask is only ever desktop entries and icons, but it solves my case and
nobody else's, and it adds a second thing to keep in sync with the NAR.

**C is the only one that works for every path already in the cache.** No client changes,
no listing changes, no NAR format change, no re-upload, and it does not depend on the
`narOffset` fix landing. The costs are real and land on infra: decompression moves to the
serving side, and CDN cache keys multiply.

## What already works in this direction

- `.ls` is a real per-store-path JSON API and is already treated as a stable public
  interface. `vlc`'s listing is 9,390 bytes on the wire for a 964-file tree, so the
  discovery half of this is cheap and already deployed.
- Fastly honours `Range` on NARs today: `curl -r 0-15` returns `206` with a correct
  `content-range`.
- Nix already has the client half of a lazy accessor:
  `makeLazyNarAccessor(NarListing, GetNarBytes)` with
  `GetNarBytes = fn(uint64_t offset, uint64_t length, Sink&)`. `RemoteFSAccessor` just
  does not use it -- it still calls `store->narFromPath()`.

## Precedent for the endpoint shape

The URL shape is already settled among three NixOS-adjacent implementations, so this would
not be inventing an interface:

- `harmonia`: `/serve/{hash}{path}`. Its README notes its own `.ls` lacks `narOffset` and
  that this is "not required for nix-index".
- Cachix: opt-in `/api/v1/cache/<cache>/serve/<storehash>/<filepath>`.
- `nar-serve` (numtide, since 2019): a proxy doing exactly this,
  `host/<store-path>/<file>` -- <https://github.com/numtide/nar-serve>. I could not reach
  a public instance, so treat it as precedent for the shape rather than something to
  depend on.

`attic` and `nix-serve` have no per-file endpoint. There is no existing Nix issue or PR
proposing HTTP `Range` against cache NARs.

## Objection: this costs NixOS money

I went looking for a cost argument in favour of this and the control killed it, so I am
stating it plainly rather than letting someone else find it.

Fastly cache state for the 264 sampled GUI-package NARs looked damning -- 243/264
`MISS, MISS`, 249/264 with zero edge hits, i.e. essentially every fetch an S3 origin read.
But those are `nixos-25.05` paths. The same probe over 400 random `nixos-unstable` paths:

```
HIT, MISS   252 (63%)      MISS, HIT    51 (13%)
HIT, HIT     93 (23%)      MISS, MISS    4  (1%)
```

99% warm. The coldness was an artifact of sampling an older channel, not a property of
long-tail indexing. An indexer over the current channel is served from the edge, where
egress is free to the project.

**So this proposal is not an infrastructure cost saving** and should not be argued as one.
It is a consumer-side latency, bandwidth and CI-time argument, plus a capability argument.
Sweeps of *older* channels are a real origin-cost case, but that is not the primary
workload, and I would rather not lead with an argument I disproved myself.

## Objection: many small requests instead of a few large ones

Measured on the same sample. Today: 264 NAR GETs + 264 `.ls` + 264 narinfo = 792 requests
for 3.148 GiB. With a per-file endpoint: 264 `.ls` + 346 `.desktop` + ~346 icon GETs = 956
requests. That is **1.21x the request count** for 1/200th the bytes.

Because the cost is so concentrated, a client can apply a size threshold and get most of
the benefit for almost no extra requests: restricting per-file fetches to the 11 packages
over 50 MB removes **64% of the transfer for 24 extra requests**. Whatever rate limits the
endpoint carried, a consumer could stay under them and still capture the bulk of the win.

## Objection: you cannot verify a single file

True, and worth stating rather than papering over. The narinfo signature covers `NarHash`
over the whole NAR, so a consumer fetching one file cannot verify it against that
signature. This is for metadata and indexing, not for anything that becomes a store path.
`.ls` is already unsigned and already relied upon, so this does not introduce a new class
of trust -- but it does not close the gap either, and a consumer that needs verification
must still fetch the whole NAR.

## Proof of concept

There is a working implementation in `cache-serve/`: a small Rust service that answers
`/serve/<storehash>/<path>` by streaming the NAR from the public cache interface,
decompressing forward to the wanted file, emitting its bytes and dropping the upstream
connection. It holds no credentials, needs no bucket access and has no write path. It ships
with a NixOS module and a patch against `terraform/cache.tf`.

Measured against `cache.nixos.org` over 24 store paths containing a desktop entry:

| | |
| --- | --- |
| bytes delivered to the client | 50,241 |
| compressed NARs those files live in | 305,513,779 |
| client-side saving | **6,080x** |
| uncompressed bytes the server decoded | 973,574,817 of 1,348,801,624 (**72%**) |
| per-request wall time | median 0.36s, p90 1.71s, max 6.45s |

The server-side number is the one I could not estimate from outside, so I want to state it
plainly rather than bury it: **a request decompresses most of its archive.** The median is
86.6% of the NAR; stopping at the wanted file saves about a quarter of the work, which is
the same order as the 20.1% that the purely client-side option D would have saved. This
endpoint does not avoid decompression. It moves it to a machine that does it once, instead
of every client doing it after paying 202x in transfer.

The tail is the part to design around: 6.45s of CPU for one request against a 700 MB NAR.

## Questions

1. Is a per-file read endpoint something infra would consider in principle? The shape I
   have built for is a path-scoped backend on the existing `fastly_service_vcl`:
   `terraform/cache.tf` already conditions behaviour on a path prefix for segmented
   caching, so `/serve/` can go to its own origin while `/nar/`, narinfo and `.ls` keep
   byte-identical behaviour. Rolling it back is deleting one backend block and one snippet.
   The remaining unknown I cannot measure from outside is cache-key multiplication at the
   edge.
2. Given that tail, I do not think Fastly Compute is the right venue -- a Wasm runtime with
   a per-request CPU budget is the wrong shape for seconds of pure decompression, and an
   origin behind the existing shield is not. Is running another origin a cost infra would
   rather not take on, in which case Compute is worth measuring properly instead?
3. If the answer to (1) is no, is seekable-zstd NAR emission (option B) worth pursuing,
   given it only ever applies to newly uploaded paths?
4. Is this better routed as an RFC? <https://github.com/NixOS/rfcs/pull/196>
   (self-describing store) looks like the natural place to negotiate a new capability, and
   I am happy to write it up there instead if that is the preferred route.

`cache-staging.nixos.org` already exists and is Terraform-managed the same way, so it is
the natural place to try this before anything touches production.

Full measurement notes, with the commands that produced every figure, are in
`MEASUREMENTS.md` alongside this draft.
