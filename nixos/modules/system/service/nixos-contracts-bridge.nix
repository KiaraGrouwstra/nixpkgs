{ config, lib, ... }:
let
  portable-lib = import ./portable/lib.nix { inherit lib; };
in
{
  contracts = lib.mapAttrs (contractType: _: {
    want = lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        _: service: lib.toList (service.contract.requests.${contractType} or { })
      ) [ ] config.system
    );
  }) config.contractTypes;

  contract.providers = lib.mapAttrs (contractType: _:
    lib.mkMerge (
      portable-lib.flattenMapServicesConfigToList (
        loc: service:
          lib.optional (loc != [ ] && service.contract.providers ? ${contractType})
            service.contract.providers.${contractType}
      ) [ ] config.system
    )
  ) config.contractTypes;
}
