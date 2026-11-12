# Command line of `wstunnel`, in a module that is not specific to a module
# class. `wstunnel` requires a subcommand. The `command` option has an
# attribute for each subcommand, and the consumer sets exactly one of them.
# `passthru.commandModules.wstunnel` of `pkgs.wstunnel` exposes this module.
# See "Modules of a package" in the Nixpkgs manual for why it is in this
# directory.
#
# The consumer sets `package`. The module of each subcommand adds its
# `settings` to its own `portable.argv`. `settings` and `portable.flags` use
# the same `portable.flagFormat`, thus `portable.flags.foo` gives `--foo`, as
# `settings.foo` does.

{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    getExe
    mkOption
    mkOrder
    types
    ;

  # Not `lib.genericModules`: the `lib` module argument may come from a
  # different Nixpkgs version than this file.
  commandLine = lib.modules.importApply ../../../../../../../lib/modules/generic/command-line.nix {
    prefix = [ "portable" ];
  };

  outerConfig = config;

  # The options that all subcommands share.
  subcommandModule = {
    imports = [ commandLine ];

    options.settings = mkOption {
      type = types.submodule {
        freeformType = types.attrsOf (
          types.oneOf [
            types.bool
            types.int
            types.str
            (types.listOf types.str)
          ]
        );
      };
      default = { };
      description = ''
        Command line arguments to pass to `wstunnel`.
        Attributes of the form `argName = true;` will be translated to `--argName`,
        and `argName = \"value\"` to `--argName value`.
      '';
      example = {
        "someNewOption" = true;
        "someNewOptionWithValue" = "someValue";
      };
    };

    config.portable.flagFormat = outerConfig.portable.flagFormat;
  };

  subcommand =
    name: module:
    mkOption {
      description = "Run `wstunnel ${name}`.";
      type = types.submoduleWith {
        modules = [
          subcommandModule
          module
        ];
      };
    };
in
{
  imports = [ commandLine ];

  options = {
    package = mkOption {
      description = "The wstunnel package to use.";
      type = types.package;
    };

    command = mkOption {
      description = ''
        The subcommand to run. Set exactly one attribute.
      '';
      type = types.attrTag {
        client = subcommand "client" ./wstunnel/client.nix;
        server = subcommand "server" ./wstunnel/server.nix;
      };
    };
  };

  config.portable = {
    executable = getExe config.package;

    # The subcommand and its arguments come after the flags of `wstunnel`, and
    # before the `argv` entries that use `lib.mkAfter`.
    argv = mkOrder 1400 (
      lib.concatLists (lib.mapAttrsToList (name: sub: [ name ] ++ sub.portable.argv) config.command)
    );

    # The format of `lib.cli.toCommandLineGNU`.
    flagFormat =
      flag:
      let
        isLong = lib.stringLength flag > 1;
      in
      {
        option = if isLong then "--${flag}" else "-${flag}";
        sep = if isLong then "=" else "";
        explicitBool = false;
      };
  };
}
