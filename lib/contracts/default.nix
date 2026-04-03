{ lib, ... }:
let
  inherit (lib) mkOption;
in
lib.mapAttrs
  (
    _: path:
    # type-check contracts defined in `lib/contracts`.
    lib.evalOption (mkOption {
      type = lib.contract.templateType;
    }) (import path { inherit lib; })
  )
  {
    fileSecrets = ./file-secrets.nix;
  }
