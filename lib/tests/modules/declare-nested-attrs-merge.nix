# Two declarations of a `nestedAttrsOf` option merge their element types.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    {
      options.value = mkOption {
        type = types.nestedAttrsOf (types.submodule { options.x = mkOption { type = types.int; }; });
      };
    }
    {
      options.value = mkOption {
        type = types.nestedAttrsOf (
          types.submodule (
            { config, ... }:
            {
              options.y = mkOption { type = types.int; };
              config.y = config.x + 1;
            }
          )
        );
      };
    }
  ];

  config.value.a.b.x = 1;
}
