# Contracts

## Design

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
    - currently opted to manually pass paths to this like `config.testing.hardcoded-secret.fileSecrets`
    - i considered manually passing just `config.testing.hardcoded-secret`, potentially standardizing over where to find the contract instances (in this case at `.fileSecrets`), but that seemed maybe too restrictive in the event some consumers would consider their contract consumption to be part of some more local name space.
    - also passing `options` seemed relevant to:
      - type `contracts."<name>".instances."<name>"`, but `config`-dependent typing broke the docs build
      - make (if we cannot alias/shadow?) an option space to configure such a provider, but:
        - making an option instance for these would make one end up with two disparate spaces
        - aliasing these failed as well, see `defaultProvider`
    - if i could make use of `options` as well, we could just maybe pass a path like `[ "testing" "hardcoded-secret" ]`, though this would also raise questions on that path (relevant for `options`) vs appending a path such as (in that case) `"fileSecrets"` (relevant for `config`)
  - `requests`
  - `instances`
- consumer
  - options _having_ `output`s rather than _being_ them
    - prevents an infinite recursion (*REPRO*: see stash, probably also prior infinite recursion discussions)

## TODO

- [ ] isolate provider rather than consumer
- [ ] eliminate API differences for modular services
- [ ] test contracts not part of `lib` with NixOS and modular services
- [ ] replace function `getInputs` with calculated module system option
- [ ] replace function `mkContract` with calculated module system option
- [ ] try using `mkContract` at the level of the consumer's option type to prevent having to essentially redefine the interface
- [ ] confirm how to handle overrides on both sides, and whether this may be simplified
- [ ] variable number of layers to address modular services' multiple instantiations without nesting it for everywhere else?
- [ ] reconsider `default` changes for `services.stash` passwords
- [ ] squash
- make branches for any optional API changes to separate choices
  - [ ] let contract test use nspawn containers
  - [ ] rm empty `default` values
  - [ ] wrap types with `interface`
  - [ ] split namespace into two layers to disambiguate contract instances between services
  - [ ] change `default`s for `services.stash` passwords to abstract out `output` links
  - [ ] add functionality to abstract out `input` links
- add implementations or tests validating our approach with the various edge cases
  - e.g. create tests using a test contract `arithmetic` with a provider `increment` doing `+1` (this might not generate configuration, but that might be fine for the scope of such a test)
  - [ ] service providing multiple contracts (e.g. SHB's [`restic`](https://shb.skarabox.com/blocks-restic.html#blocks-restic-contract-provider) / [`borgbackup`](https://shb.skarabox.com/blocks-borgbackup.html#blocks-borgbackup-contract-provider) providing for both contracts [backup](https://shb.skarabox.com/contracts-backup.html) + [database backup](https://shb.skarabox.com/contracts-databasebackup.html))
  - use in modular services
    - [ ] simple test like using secrets in existing modular service
    - [ ] [modular service with multiple instantiations consuming contracts](https://github.com/NixOS/nixpkgs/issues/428084#issuecomment-3904908631)
    - [ ] [coordinating across modular services to port to modular services existing nixos service modules spanning disparate systemd services](https://github.com/NixOS/nixpkgs/issues/490688)
  - [ ] use in Darwin/home-manager?
  - [ ] [side effects](https://github.com/ibizaman/selfhostblocks/issues/467#issuecomment-3258197623)
    - seem already handled with secrets?
  - [ ] [services consuming contracts they also provide for]()
  - [ ] [cross-node use of contracts](https://github.com/ibizaman/selfhostblocks/issues/541)
    - could still work now that I make it error on missing `defaultProvider`?
  - [ ] [contracts combining multiple existing contracts](https://github.com/ibizaman/selfhostblocks/issues/467#issuecomment-4063155555)
  - [ ] breaking changes to contract interfaces - could `mkAliasOptionModule` work with this weird `lib` / `config` dichotomy?
  - [ ] gracefully handling changes to contract names (see above?)
  - UI generation for contract provider
    - [ ] pick default provider by e.g. `enum` of provider names
      - [ ] how to migrate such untyped serializable string values on contract name changes
    - [ ] reinstate providers' `options` reference (or just use path like `[ "testing" "hardcoded-secret" ]` again to obtain references to both the `config` and the `options` - tho this would distinguish the path from `.fileSecrets` used now) to know what options should be visualized to configure this provider
  - backward-compatible changes to contracts - seems trivial, but having trouble finding prior discussion
  - merging options - should be fine, i think we should not have special needs here
