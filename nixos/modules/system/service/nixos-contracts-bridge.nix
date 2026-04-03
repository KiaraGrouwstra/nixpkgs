{ config, lib, ... }:
let
  portable-lib = import ../../../../lib/services/lib.nix { inherit lib; };
in
{
  contracts = lib.mapAttrs (contractType: _: {
    want = lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        _: service: lib.toList (service.contracts.${contractType}.want or { })
      ) [ ] config.system
    );
    providers = lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        _: service:
          lib.mapAttrsToList (name: provider: {
            ${name} = provider;
          }) (service.contracts.${contractType}.providers or { })
      ) [ ] config.system
    );
  }) config.contractTypes;
}
