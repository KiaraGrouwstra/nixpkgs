# Arguments of `wstunnel client` that come after the subcommand, in a module
# that is not specific to a module class. `command.client` of `../wstunnel.nix`
# uses it as a submodule. That submodule also has the options that all
# subcommands share. See "Modules of a package" in the Nixpkgs manual for why it
# is in this directory.

{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkAfter
    mkMerge
    mkOption
    mkOrder
    types
    ;
in
{
  options = {
    connectTo = mkOption {
      description = "Server address and port to connect to.";
      type = types.str;
      example = "https://wstunnel.server.com:8443";
    };

    settings = mkOption {
      type = types.submodule {
        options = {
          http-headers = mkOption {
            type = types.coercedTo (types.attrsOf types.str) (lib.mapAttrsToList (n: v: "${n}:${v}")) (
              types.listOf types.str
            );
            default = { };
            example = {
              "X-Some-Header" = "some-value";
            };
            description = ''
              Custom headers to send in the upgrade request
            '';
          };
        };
      };
    };
  };

  config.portable.argv = mkMerge [
    (mkOrder 1250 (lib.cli.toCommandLine config.portable.flagFormat config.settings))
    (mkAfter [ config.connectTo ])
  ];
}
