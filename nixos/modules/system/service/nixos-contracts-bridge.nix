{ config, lib, ... }:
let
  portable-lib = import ./portable/lib.nix { inherit lib; };
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
        loc: service:
          lib.optional (loc != [ ] && service.contract.providers ? ${contractType})
            { ${lib.last loc} = service.contract.providers.${contractType}; }
      ) [ ] config.system
    );
  }) config.contractTypes;
}
