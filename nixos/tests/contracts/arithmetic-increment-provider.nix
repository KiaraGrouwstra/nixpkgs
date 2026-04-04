# Modular service provider for the arithmetic contract: returns request.value + 1.
# Shared across contract tests that need an increment provider as a modular service.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.contractTypes.arithmetic) extend;
in
{
  _class = "service";
  options.arithmetic = mkOption {
    description = "Arithmetic contract instances fulfilled by this increment provider.";
    type = types.nestedAttrsOf (
      types.submodule [
        {
          options = {
            request = mkOption { type = extend.request { }; };
            result = mkOption {
              default = { };
              type = extend.result { };
            };
          };
        }
        (
          { config, ... }:
          {
            config.result.value = lib.mkDefault (config.request.value + 1);
          }
        )
      ]
    );
  };
  config = {
    arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment = config.arithmetic;
    process.argv = [ "/run/current-system/sw/bin/true" ];
  };
}
