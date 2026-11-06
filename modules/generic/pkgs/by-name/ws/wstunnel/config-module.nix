# The restrictions file of `wstunnel server`, as a module that maps an option to
# the file. `pkgs.wstunnel.configFiles` exposes it, so that a system that does
# not use NixOS can also evaluate it. `pkgs.wstunnel.configModule` exposes this
# file, to use it in a different `pkgs.configFiles` call.
#
# This option is not named `settings`, because the command modules of `wstunnel`
# declare `settings`, which has the flags. See "Modules of a package" in the
# Nixpkgs manual.
# Non-module dependencies. `pkgs.configFiles` gives them.
{ formats }:

{ config, lib, ... }:
let
  # The tags are part of the format of the file, for example `!Tunnel`.
  format = formats.yaml_1_2 { tags = true; };
in
{
  options.restrictions = lib.mkOption {
    type = lib.types.nullOr format.type;
    default = null;
    example = lib.literalExpression ''
      [
        {
          name = "tcp to 443";
          match = [ { "!PathPrefix" = "^.*$"; } ];
          allow = [
            {
              "!Tunnel" = {
                protocol = [ "Tcp" ];
                port = [ 443 ];
                host = "^.*$";
                cidr = [ "0.0.0.0/0" "::/0" ];
              };
            }
          ];
        }
      ]
    '';
    description = ''
      Rules for the tunnels that the server allows, as the `restrictions` list
      of the file that `--restrict-config` reads.
      A key that starts with `!` is a YAML tag.
      See <https://github.com/erebe/wstunnel/blob/main/restrictions.yaml>.

      When `null`, this module does not write the file.
    '';
  };

  config.portable.files = lib.mkIf (config.restrictions != null) {
    "restrictions.yaml".source = format.generate "restrictions.yaml" {
      inherit (config) restrictions;
    };
  };
}
