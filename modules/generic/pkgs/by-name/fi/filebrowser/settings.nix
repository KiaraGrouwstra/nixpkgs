# The settings of FileBrowser that are both a flag and a key of the
# configuration file, as a module that is not specific to a module class.
# `commands/filebrowser.nix` and `config-module.nix` import this file. The module
# system evaluates a path one time, thus the two imports do not clash. A copy of
# this file at a different path clashes.
#
# This module must not use `pkgs`, because a command module has no `pkgs`.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.settings = mkOption {
    default = { };
    description = ''
      Settings for FileBrowser.
      Refer to <https://filebrowser.org/cli/filebrowser#options> for all supported values.
    '';
    type = types.submodule {
      options = {
        address = mkOption {
          default = "localhost";
          description = ''
            The address to listen on.
          '';
          type = types.str;
        };

        port = mkOption {
          default = 8080;
          description = ''
            The port to listen on.
          '';
          type = types.port;
        };

        root = mkOption {
          default = "/var/lib/filebrowser/data";
          description = ''
            The directory where FileBrowser stores files.
          '';
          type = types.path;
        };

        database = mkOption {
          default = "/var/lib/filebrowser/database.db";
          description = ''
            The path to FileBrowser's Bolt database.
          '';
          type = types.path;
        };
      };
    };
  };
}
