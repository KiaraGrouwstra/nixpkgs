# An empty attribute set is a namespace, not a leaf with the default values.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.value = mkOption {
    type = types.nestedAttrsOf (
      types.submodule {
        options.x = mkOption {
          type = types.int;
          default = 1;
        };
      }
    );
  };

  config.value = {
    a = { };
    b.c = { };
    d.x = 2;
    e.f = lib.mkIf false { x = 3; };
  };
}
