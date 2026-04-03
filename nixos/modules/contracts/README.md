# Contracts

## Architecture

The contracts system is split across two layers:

- **`lib/contracts/`** - system-agnostic contract infrastructure
  - `module.nix` - generic contracts module (defines `contractTypes`, `contracts`, `_upstreamContracts`); importable into any module system (NixOS, home-manager, nix-darwin)
  - `default.nix` - nixpkgs-shipped contract definitions and computed helpers (`mkContract`, `extend`)
  - `lib.nix` - helper functions (`evalOption`, `extendOption`, `extendSubmodule`) and `templateType`
- **`nixos/modules/contracts/`** - NixOS wrapper that imports the generic module and seeds `lib.contracts`

For modular services, two additional layers connect services to contracts:

- **`lib/services/lib.nix`** - `configure` function that builds a `serviceSubmodule` type with contract integration via `_upstreamContracts`
- **Bridge module** (per system) - collects `contracts.<type>.want` and `contracts.<type>.providers` from services into the containing system's contract namespace; see `nixos/modules/system/service/nixos-contracts-bridge.nix`

### Adding contracts to a new module system

1. Import `lib/contracts/module.nix` and seed `config.contractTypes = lib.contracts` (see this directory's `default.nix`)
2. If the system supports modular services: call `lib/services/lib.nix`'s `configure`, add a bridge module, and write a service manager integration (see `nixos/modules/system/service/systemd/system.nix`)

## Design decisions

- `lib`
  - usable when building docs, making this a good place from which to source types
- `config`
  - can be contributed to from different modules, making this a good place for tracking contracts' providers and consumers
  - > Note that the split between `lib.contracts` and `config.contracts` ensures types
    > would not have to depend on `config`, which would break the build of the manual.
  - `meta`
    - is a module system attribute too, but that wasn't helpful in `lib` where we're storing contracts first.
      > Note that, while `meta` is already a valid module attribute next to `config` and `options`,
      > it is added as an explicit configuration option here to facilitate transferring this info from `lib.contracts`.
  - `interface`
    - this wrapper around input/output may have technically been unnecessary, but it seemed clean-ish maybe
  - `defaultProvider`
    - named to prevent name collision with `default`, but maybe reconsider
    - previously tried typing as an `attrTag` as its values shadowing the providers' options, but did not get this to work so far. such aliasing is normally reserved for option renames, and in fact `imports` (where `mkAliasOptionModule` is usually placed) may not rely on `config`. an attempt to locally place the `mkAliasOptionModule` like `defaultProvider = mkOption { type = submodule (mkAliasOptionModule ...); };` failed as well, potentially due to scoping issues.
    - considered different types, settled on directly picking providers to for now match types between default vs overrides. note that there are considerations on such interfaces for:
      - LSPs: prefers typed stuff to prevent typos
      - GUIs: prefers serializable things (like enum of strings)
      - LLMs: prefers shorter code for lower token use
      - the module system: want to merge configurations with various priorities, so don't like e.g. mutually exclusive settings such as `users.users.<name>`'s `isNormalUser` + `isSystemUser`
  - `providers`
    - consumers and providers use the same `contracts.<type>.providers.<name>` API in both NixOS modules and modular services
    - the bridge module automatically collects providers set by modular services into the containing system's contract namespace
    - currently opted to manually pass paths to this like `config.testing.hardcoded-secret.fileSecrets`
    - i considered manually passing just `config.testing.hardcoded-secret`, potentially standardizing over where to find the contract instances (in this case at `.fileSecrets`), but that seemed maybe too restrictive in the event some consumers would consider their contract consumption to be part of some more local name space.
    - also passing `options` seemed relevant to:
      - type `contracts."<name>".instances."<name>"`, but `config`-dependent typing broke the docs build
      - make (if we cannot alias/shadow?) an option space to configure such a provider, but:
        - making an option instance for these would make one end up with two disparate spaces
        - aliasing these failed as well, see `defaultProvider`
    - if i could make use of `options` as well, we could just maybe pass a path like `[ "testing" "hardcoded-secret" ]`, though this would also raise questions on that path (relevant for `options`) vs appending a path such as (in that case) `"fileSecrets"` (relevant for `config`)
  - `requests`
    - read-only, derived from `want`; in modular services, delegates to the containing system's aggregated requests via `_upstreamContracts`
  - `instances`
  - `_upstreamContracts`
    - connects a modular service's contract namespace to the containing system's resolved contracts
    - read-side options (`requests`, `defaultProvider`, `results`) delegate to upstream; write-side options (`want`, `providers`) remain local for the bridge to collect
    - avoids circularity: the bridge reads `want`/`providers` (local), and the seed injects `requests`/`defaultProvider` (resolved) - these are disjoint paths through the fixpoint
- consumer
  - options _having_ `output`s rather than _being_ them
    - prevents an infinite recursion (*REPRO*: see stash, probably also prior infinite recursion discussions)

## TODO

- [ ] reconsider `default` changes for `services.stash` passwords
- [ ] squash
- make branches for any optional API changes to separate choices
  - [ ] rm empty `default` values
  - [ ] wrap types with `interface`
  - [ ] change `default`s for `services.stash` passwords to abstract out `output` links
  - [ ] add functionality to abstract out `input` links
- add implementations or tests validating our approach with the various edge cases
  - [ ] [side effects](https://github.com/ibizaman/selfhostblocks/issues/467#issuecomment-3258197623)
    - seem already handled with secrets?
  - [ ] [services consuming contracts they also provide for]()
    - could this still work now that I make it error on missing `defaultProvider`?
    - such services might be part of a hierarchy, e.g. file secrets (secret managers), tls certs (nginx, CA)
    - self-referential case itself probably not real
  - [ ] [contracts combining multiple existing contracts](https://github.com/ibizaman/selfhostblocks/issues/467#issuecomment-4063155555)
  - UI generation for contract provider
    - [ ] reinstate providers' `options` reference (or just use path like `[ "testing" "hardcoded-secret" ]` again to obtain references to both the `config` and the `options` - tho this would distinguish the path from `.fileSecrets` used now) to know what options should be visualized to configure this provider
  - [ ] home-manager integration
  - [ ] nix-darwin integration
