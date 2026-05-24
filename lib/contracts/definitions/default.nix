# collection of contract templates, defined in `lib` so we can still build the manual.
# declarations of individual contracts follow the type in `./definition-type.nix`.
{ lib, ... }:
lib.mapAttrs (
  name: path:
  let
    contract = lib.evalOption (lib.mkOption {
      type = lib.contract.definitionType;
    }) (import path { inherit lib; });
  in
  contract
  // {
    # Resolve the contract's `mkProviderType` against a NixOS module's `config`,
    # preferring the bridge (`config.contracts.<name>.mkProviderType`) when
    # available - the bridge pre-binds `_requests` so consumer `want` request
    # data is forwarded into each leaf (see `mkProviderType`'s `_requests`
    # parameter in `../definition-type.nix`). Falls back to the pure lib
    # function when `config.contracts` is absent (e.g. inside the manual
    # docs build's per-module sandbox, where the contracts module is not
    # imported); the lib version produces an identical option type shape,
    # only without runtime want forwarding, which is irrelevant to rendered docs.
    mkProviderTypeFor =
      moduleConfig:
      moduleConfig.contracts.${name}.mkProviderType or contract.mkProviderType;
  }
) { fileSecrets = ./file-secrets.nix; }
