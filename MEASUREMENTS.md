# Serving individual files from `cache.nixos.org` -- measurements

All figures measured 2026-08-28 against the live `cache.nixos.org`. Every command is
included so the numbers can be re-derived. Sample path used throughout:
`/nix/store/09h3yc7b74r3vydcicf26civfspagnpa-vlc-3.0.23-2`.

## Summary of what changed relative to the starting assumptions

Three of the premises I started from turned out to be wrong, and one of them inverts the
shape of the proposal:

1. **`narOffset` is not a missing feature -- it is a regression, ~10 weeks old.**
   `cache.nixos.org` published `narOffset` on every regular file in every `.ls` listing
   from at least Dec 2017 through 2026-06-15, and publishes none from 2026-06-23 onward.
2. **The apparent "single-file listings have offsets, directory listings do not"
   discrepancy does not exist.** It was an artifact of era, not of shape.
3. **Option D (prefix-range decode) is dead on measurement**, not merely weak: it saves
   20% of transfer, and the median package needs 94% of its NAR.

## 1. `.ls` is a real, public, per-store-path API

```console
$ curl -sSI https://cache.nixos.org/09h3yc7b74r3vydcicf26civfspagnpa.ls
HTTP/2 200
content-type: application/json
content-encoding: zstd
accept-ranges: bytes
content-length: 9390
x-cache: HIT, HIT
```

9,390 bytes on the wire, 81,616 decoded, 964 regular files. Confirmed.

## 2. `narOffset` disappeared from published listings between 2026-06-15 and 2026-06-23

`content-encoding` on the `.ls` response is a free discriminator for the two eras, so a
single `HEAD` per path classifies it without downloading or parsing a body:

| `content-encoding` | era | `narOffset` |
| --- | --- | --- |
| `br` | up to 2026-06-15 | present on every regular file |
| `zstd` | from 2026-06-23 | absent on every regular file |

Sampling 2,500 random local store paths (which span 2017-2026 by upload date), 1,150 of
which are published:

```console
$ find /nix/store -maxdepth 1 -mindepth 1 -printf '%f\n' | grep -v '\.drv$' \
    | shuf -n 2500 --random-source=<(yes) > wide.txt
$ xargs -a wide.txt -P 48 -n1 ./head1.sh > wide.tsv   # HEAD, record encoding + last-modified
```

```
month        br  zstd          latest br     : 2026-06-15
  2026-05     42     0         earliest zstd : 2026-06-23
  2026-06     39    38         total 1150   br 311   zstd 572
  2026-07      0   162
  2026-08      0   372
```

The step is clean -- no interleaving at the boundary. Cross-checked against three
channel closures by fetching bodies and counting entries:

```console
$ xz -dc sp_nixos-21.05.xz | shuf -n 20 | sed 's|/nix/store/||' > old.txt
$ # per path: curl -sS --compressed .../<hash>.ls, count regular files vs those with narOffset
nixos-21.05: paths=20 files=819 offsets=819   (br)
nixos-23.05: paths=20 files=552 offsets=552   (br)
nixos-25.05: paths=20 files=277 offsets=277   (br)
```

versus 103 current-era paths from the same sweep: **20,226 regular files, 0 offsets**.

> **Measurement trap.** My first pass at this reported "offsets absent everywhere,
> including old paths". That was wrong: old bodies are brotli-encoded, and I was piping
> every body through `zstd -dc`, which failed silently and yielded zero files -- which
> reads identically to "zero files with offsets". Use `curl --compressed` and let curl
> dispatch on the header. The corrected sweep is the one above.

### Cause

> An earlier revision of these notes blamed `store->getFSAccessor()` at
> `subprojects/crates/nix-utils/src/nix.cpp:315` in Hydra. That was read off a stale local
> checkout: <https://github.com/NixOS/hydra/pull/1729> deleted that code on 2026-05-12.
> The real cause is below, and it is a different mechanism -- the listing *is* built from
> the NAR stream, the offsets are just never recorded.

Hydra PR 1729 ("Use harmonia for NAR listings instead of Nix C++ FFI", merged 2026-05-12)
replaced the C++ FFI call with `harmonia_file_nar::parse_nar_listing`, invoked from
`subprojects/crates/binary-cache/src/lib.rs:684` via `nar_listing()` at `lib.rs:1327`,
which streams the real NAR. But `parse_nar_listing` hardcodes the offset:

```rust
let info = NarFileInfo {
    size,
    nar_offset: None, // TODO: track byte offset
};
```

<https://github.com/nix-community/harmonia/blob/4ec14354eb77650607c529364256174e0b731323/harmonia-file-nar/src/listing.rs#L44-L49>

`NarFileInfo` declares the field with `#[serde(rename = "narOffset", ...,
skip_serializing_if = "Option::is_none")]`, which is why it vanishes from the JSON rather
than serializing as `null`. The parser exposes no cumulative byte position, so fixing it
means threading one through, not just filling in the `TODO`.

### Harmonia side: an unfinished `TODO`, not a regression

`git log -S nar_offset --all` in harmonia returns four commits:

| commit | date | what |
| --- | --- | --- |
| `1baa3fd` | 2024-11-03 | filesystem listing reimplemented in Rust; `nar_offset: None`, plus an `unset_nar_offset` helper so the `nix nar ls` comparison test ignores it |
| `574ce55` | 2026-05-10 | `harmonia-file` cap-std rewrite |
| `12372b4` | 2026-05-10 | splits out `harmonia-file-nar`; introduces `parse_nar_listing` carrying `nar_offset: None, // TODO: track byte offset` |
| `a404557` | 2026-05-11 | rewrites the test-normalization comment |

No harmonia revision has ever populated the field. The NAR-listing parser was written two
days before Hydra adopted it in `a5c08935` (PR 1729, in master 2026-05-12, pinning
harmonia `e358a9bc`). So on harmonia's side this is unfinished new code; the regression is
in what `cache.nixos.org` publishes, and it was produced by Hydra pointing its listing
generation at it.

### Pinning the deploy

The changeover is one infra commit, not a gradual rollout. NixOS/infra `bb14833`
("mimas: enable new hydra-queue-runner", committed 2026-06-17) bumps the `hydra` flake
input past PR 1729:

```console
$ git show bb14833:flake.lock   | jq -r '.nodes.hydra.locked.rev'   # d001b820, 2026-06-17
$ git show bb14833~1:flake.lock | jq -r '.nodes.hydra.locked.rev'   # a40d4286, 2026-03-16
$ cd hydra
$ git merge-base --is-ancestor a5c08935 d001b820 && echo "deployed: includes PR 1729"
deployed: includes PR 1729
$ git merge-base --is-ancestor a5c08935 a40d4286 || echo "previous: excludes PR 1729"
previous: excludes PR 1729
```

and, in the same commit, flips the compression of the objects it writes:

```diff
-store_uri = s3://nix-cache?...&write-nar-listing=1&ls-compression=br&log-compression=br&...
+store_uri = s3://nix-cache?...&write-nar-listing=1&compression=zstd&ls-compression=zstd&log-compression=zstd&...
```

2026-06-17 falls exactly between the last `br` listing (2026-06-15) and the first `zstd`
one (2026-06-23). This also explains why `content-encoding` discriminates the eras so
cleanly: the encoding change and the offset loss are not two correlated events, they are
one commit. The harmonia revision pinned by the deployed hydra is `12c67425` (2026-06-03),
which contains `nar_offset: None`.

No test catches it: `parse_nar_listing` has one test that does not assert offsets, and the
round-trip test against `nix nar ls` lives on harmonia's filesystem-listing path
(`harmonia-cache/src/narlist.rs:216-220`) and deliberately strips `narOffset` before
comparing.

Nix's own writer still emits offsets, via `parseNarListing` over the NAR byte stream
(`src/libstore/binary-cache-store.cc:206`), which is why `nix copy --to
's3://...?write-nar-listing=1'` is unaffected. The emission condition itself
(`src/libutil/nar-listing.cc:143`) collapses zero and absent, but that is not the cause
here.

The `write-nar-listing` and `ls-compression` settings exist on both sides but neither
controls offset presence.

## 3. Current Nix emits offsets locally

```console
$ nix nar dump-path /nix/store/di26b1kkbammy0sj70nq5qzvfrh78wxl-coreutils-9.11 > cu.nar
$ nix nar ls --json -R cu.nar /
/bin/coreutils                    {"executable":true,"narOffset":3208,"size":1768632,"type":"regular"}
/libexec/coreutils/libstdbuf.so   {"executable":true,"narOffset":1790816,"size":15808,"type":"regular"}
```

2 of 2 regular files carry offsets. Nix 2.34.8. Confirmed.

## 4. Published NARs are single-frame zstd

This is what makes an offset non-addressable.

```console
$ curl -sS https://cache.nixos.org/nar/1sqwsp...nar.zst -o vlc.nar.zst
$ zstd -l vlc.nar.zst
Frames  Skips  Compressed  Uncompressed  Ratio  Check  Filename
     1      0    18.6 MiB                        None  vlc.nar.zst
```

Checked on five further NARs built in Aug 2026, all with `NarSize` well over the 16 MiB
that would force a frame boundary if multi-frame emission were enabled:

```
clay-0.16.1                       NarSize=25223976  FileSize=3137570   frames=1 skips=0
amazonka-serverlessrepo-2.0       NarSize=28136816  FileSize=2998076   frames=1 skips=0
ocaml5.5.0-bytestring-0.0.8       NarSize=29761480  FileSize=9026565   frames=1 skips=0
openvmm-0-unstable-2025-03-13     NarSize=29981992  FileSize=8497364   frames=1 skips=0
source-serif-4.005                NarSize=30153232  FileSize=11178326  frames=1 skips=0
```

Nix merged per-16-MiB multi-frame zstd emission in Apr 2026
(<https://github.com/NixOS/nix/pull/15550>), motivated by parallel decode rather than
seeking. That change is **not** reflected in what Hydra uploads -- Hydra compresses with
its own Rust code. So option B is a recompress-everything change, not merely
"add a seek table to what we already emit".

## 5. The CDN honours `Range`

```console
$ curl -sSI -r 0-15 https://cache.nixos.org/nar/1sqwsp...nar.zst
HTTP/2 206
content-range: bytes 0-15/19501616
x-cache: HIT, HIT
```

Confirmed. Range works at the HTTP layer today; it is the compression format, not
Fastly, that blocks random access.

## 6. The win, for the real workload

Random sample of 8,000 of the 205,358 store paths in the `nixos-25.05` channel closure
(chosen because that era still carries `narOffset`, which option D needs). 264 paths
contain at least one `share/applications/*.desktop` -- 3.30%. Wanted payload = those
`.desktop` files plus icons under `share/icons/` and `share/pixmaps/` in the same path.

```console
$ python3 gui_measure.py sample_2505.txt gui_2505.jsonl
```

| quantity | value |
| --- | --- |
| whole-NAR transfer (compressed, what the script costs today) | **3.148 GiB** |
| uncompressed NAR bytes | 8.976 GiB |
| wanted payload | **15.95 MiB** (1.04 MiB `.desktop` + 14.92 MiB icons) |
| amplification vs compressed transfer | **202x** |
| amplification vs uncompressed NAR | 576x |

Per-package ratio: median 72.5x, p90 5,044x, max 1,724,620x (`zap-2.16.1`), min 0.17x.

Extrapolating linearly to the channel: ~6,777 desktop-entry paths, **~81 GiB** of
transfer for ~410 MiB of payload. (The real script runs over `outpaths.nix`, a different
denominator, so treat the 202x ratio as the robust figure and the 81 GiB as
order-of-magnitude.)

### The cost is extremely concentrated

| | |
| --- | --- |
| 50% of transfer | top 5 packages (2%) |
| 90% of transfer | top 55 packages (21%) |
| packages > 50 MB compressed | 11 (4.2%), 2.023 GiB = **64% of transfer** |
| ...their payload | 0.18 MiB -> **11,333x** |

At the other end, icon-theme-ish packages are already efficient whole-NAR: `diodon`
0.17x, `sequeler` 0.20x -- the payload is most of the package. A client should keep
fetching those whole. The pathology is entirely "large package, one small `.desktop`,
no icons": `zap`, `eclipse-platform`, `react-native-debugger`.

## 7. Option D (prefix-range decode) measured: 20% saving. Dead.

Given offsets, fetch bytes `0..maxOffset` and stream-decompress, discarding until the
wanted file. NAR entries are sorted, and `share/` sorts near the end -- which is exactly
where `.desktop` files and icons live.

Over the same 264 packages (all of which have offsets):

| | |
| --- | --- |
| uncompressed NAR bytes | 8.976 GiB |
| prefix bytes to `maxOffset` | **7.170 GiB (79.9%)** |
| per-package prefix fraction | median **94.1%**, p10 32.2%, p90 100.0% |
| saving vs whole NAR | **20.1%** |

This is the honest zero-ask baseline, and it does not clear the bar. It also requires
`narOffset`, which current listings no longer carry. Any proposal for B or C only has to
beat a 20% saving.

## 8. Who pays: the CDN control

Fastly cache state for the 264 GUI-package NARs (`HEAD`, which does not populate):

```
MISS, MISS   243 (92%)     hits=0: 249/264
HIT, MISS     18
MISS, HIT      3
```

That looks like a strong "indexing sweeps hit cold objects, and origin reads are the
actual S3 cost" argument. **The control kills it.** The same probe over 400 random
`nixos-unstable` paths:

```
HIT, MISS    252 (63%)
HIT, HIT      93 (23%)
MISS, HIT     51 (13%)
MISS, MISS     4  (1%)
```

99% are warm at some tier. The coldness I measured is an artifact of sampling an
*older* channel, not a property of long-tail indexing. So: an indexer over the
**current** channel is served almost entirely from the Fastly edge, where egress is free
to the project (per the 2023 Discourse thread on disabling anonymous direct S3 access,
CDN traffic is free and origin/S3 is the cost). **This proposal should not be argued on
NixOS infrastructure cost.** It is a consumer-side latency, bandwidth and CI-time
argument. Sweeps of older channels are a genuine origin-cost case, but that is not the
primary workload.

## 9. Prior art

- **`nar-serve`** (numtide, since 2019) -- proxy serving one file per GET,
  `host/<store-path>/<file>`. <https://github.com/numtide/nar-serve>. The hostname I
  tried (`nar-serve.numtide.com`) does not resolve, so treat it as precedent for the URL
  shape rather than as a dependency one could use today.
- **`harmonia`** -- `/serve/{hash}{path}`. Its README notes its own `.ls` lacks
  `narOffset` and that this is "not required for nix-index".
- **Cachix** -- opt-in `/api/v1/cache/<cache>/serve/<storehash>/<filepath>`.
- **`attic`**, **`nix-serve`** -- no per-file endpoint.
- **`nix-index`** -- consumes `.ls` for `type`/`size`/`executable`/`entries`/`target`
  only; needs no offsets. Useful evidence that `.ls` is treated as a stable public
  interface.
- Nix already has the client half: `makeLazyNarAccessor(NarListing, GetNarBytes)` in
  `src/libutil/include/nix/util/nar-accessor.hh`, with
  `GetNarBytes = fn(uint64_t offset, uint64_t length, Sink&)`. But
  `RemoteFSAccessor` still calls `store->narFromPath()`, so
  `nix store cat --store https://cache.nixos.org` downloads the whole NAR.
- Relevant open RFCs: <https://github.com/NixOS/rfcs/pull/195> (binary cache index
  protocol -- membership only, not per-file) and
  <https://github.com/NixOS/rfcs/pull/196> (self-describing store, `nix-store.json`),
  which is the natural place to negotiate a new capability.
- No Nix issue or PR proposes HTTP Range against cache NARs; "seekable" returns nothing
  across `org:NixOS`.

## 10. Verification and trust

The narinfo signature covers `NarHash` over the whole NAR, so a consumer that fetches
one file cannot verify it against that signature. Stated plainly: this is for metadata
and indexing, not for anything that becomes a store path. `.ls` is already unsigned and
already relied upon by `nix-index`, so per-file fetch does not introduce a new class of
trust -- but it does not remove the gap either, and a consumer that needs verification
must still fetch the whole NAR.

## Reproduction

Scripts in the scratchpad:
`gui_measure.py` (phase-A scan + payload/offset accounting), `head1.sh` (era
classification by `content-encoding`), `narinfo1.sh`, `xc.sh` (Fastly cache state).
Sampling uses `shuf --random-source=<(yes)` so it is deterministic.
