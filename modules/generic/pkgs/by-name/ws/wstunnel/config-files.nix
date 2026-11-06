# The inputs of `pkgs.configFiles`. `nixos/modules/services/networking/wstunnel.nix`
# imports this file by path.
{
  name = "wstunnel";
  modules = [ ./config-module.nix ];
}
