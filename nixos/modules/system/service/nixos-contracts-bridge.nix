{ config, lib, ... }:
let
  portable-lib = import ./portable/lib.nix { inherit lib; };
in
{
  contracts = lib.mapAttrs (contractType: _: {
    want = lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        _: service: lib.toList (service.contractRequests.${contractType} or { })
      ) [ ] config.system
    );
    providers = lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        loc: service:
          lib.optional (loc != [ ] && service.contractProviders ? ${contractType})
            { ${lib.last loc} = service.contractProviders.${contractType}; }
      ) [ ] config.system
    );
  }) config.contractTypes;
}
