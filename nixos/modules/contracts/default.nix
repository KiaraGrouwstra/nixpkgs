# NixOS contracts wrapper - imports the generic contracts module and seeds
# nixpkgs-shipped contract types.
#
# To add contracts support to another module system (home-manager, nix-darwin),
# create an equivalent module:
#
#   { lib, ... }:
#   {
#     imports = [ <nixpkgs/lib/contracts/module.nix> ];
#     config.contractTypes = lib.contracts;
#   }
#
# This gives the system `config.contracts.*` with all nixpkgs contract types.
# To also support modular services, add a bridge module and a service manager
# integration; see `nixos/modules/system/service/` for the NixOS reference.
{ lib, ... }:
{
  # contracts use `config` - not available in the docs build sandbox.
  meta.buildDocsInSandbox = false;
  imports = [ ../../../lib/contracts/module.nix ];
  config.contractTypes = lib.contracts;
}
