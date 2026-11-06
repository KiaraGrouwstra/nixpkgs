# Configuration of FileBrowser, as a module that maps the options to the file
# that FileBrowser reads. `pkgs.filebrowser.configFiles` exposes it, so that a
# system that does not use NixOS can also evaluate it.
# `pkgs.filebrowser.configModule` exposes this file, to use it in a different
# `pkgs.configFiles` call.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  format = pkgs.formats.json { };
in
{
  imports = [ ./settings.nix ];

  # This declaration has only a type, thus it merges with `./settings.nix`. Only
  # a configuration file can hold a key that this module does not know. Without
  # this module, such a key is an error, and is not silently ignored.
  options.settings = lib.mkOption {
    type = lib.types.submodule {
      freeformType = format.type;
    };
  };

  config.portable.files."config.json".source = format.generate "config.json" config.settings;
}
