# Command line of `filebrowser`, in a module that is not specific to a module
# class. `nixos/modules/services/web-apps/filebrowser.nix` uses it, and
# `passthru.commandModules.filebrowser` of `pkgs.filebrowser` exposes it. See
# "Modules of a package" in the Nixpkgs manual for why it is in this directory.
#
# This module does not set `--config`. The consumer sets
# `portable.flags.config` to the configuration file.

{
  lib,
  config,
  ...
}:
{
  imports = [
    # Not `lib.genericModules`: the `lib` module argument may come from a
    # different Nixpkgs version than this file.
    (lib.modules.importApply ../../../../../../../lib/modules/generic/command-line.nix {
      prefix = [ "portable" ];
    })
    ../settings.nix
  ];

  options.package = lib.mkOption {
    description = "The filebrowser package to use.";
    type = lib.types.package;
  };

  config = {
    portable.executable = lib.getExe config.package;

    portable.flagFormat = flag: {
      option = "--${flag}";
      explicitBool = false;
      sep = null;
    };

    # When a configuration file has the same keys, the two values are equal, and
    # the flag has priority.
    portable.flags = {
      inherit (config.settings)
        address
        port
        root
        database
        ;
    };
  };
}
