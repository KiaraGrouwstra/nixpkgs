{ config, lib, ... }:
{
  contracts = lib.mapAttrs (contractType: _: {
    requests = lib.mkMerge (
      (import ./portable/lib.nix { inherit lib; }).flattenMapServicesConfigToList (
        _: service: lib.toList (service.contractRequests.${contractType} or { })
      ) [ ] config.system
    );
  }) config.contractTypes;
}
