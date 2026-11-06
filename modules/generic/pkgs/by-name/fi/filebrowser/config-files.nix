# The inputs of `pkgs.configFiles`. `nixos/modules/services/web-apps/filebrowser.nix`
# imports this file by path.
{
  name = "filebrowser";
  modules = [ ./config-module.nix ];
}
