# Contracts bridge: collects `contracts.<type>.want` and `contracts.<type>.providers`
# from all modular services and merges them into the containing system's contract
# namespace. This is the NixOS reference implementation.
#
# To support modular services in another system (home-manager, nix-darwin),
# create an equivalent bridge that walks your system's service tree:
#
#   { config, lib, ... }:
#   let
#     portable-lib = import <nixpkgs/lib/services/lib.nix> { inherit lib; };
#   in
#   {
#     contracts = lib.mapAttrs (contractType: _: {
#       want = lib.mkMerge (
#         portable-lib.flattenMapServicesConfigToList (
#           _: service: lib.toList (service.contracts.${contractType}.want or { })
#         ) [ ] config  # ← root of your service tree
#       );
#       providers = lib.mkMerge (
#         portable-lib.flattenMapServicesConfigToList (
#           _: service:
#             lib.mapAttrsToList (name: provider: {
#               ${name} = provider;
#             }) (service.contracts.${contractType}.providers or { })
#         ) [ ] config  # ← root of your service tree
#       );
#     }) config.contractTypes;
#   }
#
# The `config` argument to `flattenMapServicesConfigToList` should be the root
# of the service tree (for NixOS: `config.system`, which has `config.system.services`).
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
