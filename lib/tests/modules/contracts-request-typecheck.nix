# Tests that contract requests are type-checked: setting a request option to
# the wrong type (e.g. a string where an int is expected) must produce an
# evaluation error.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.contractTypes.arithmetic) extend;
in
{
  imports = [ ./contracts-arithmetic-contract.nix ];

  options.services.increment.arithmetic = mkOption {
    type = types.nestedAttrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            request = mkOption { type = extend.request { }; };
            result = mkOption { type = extend.result { }; };
          };
          config.result.value = lib.mkDefault (config.request.value + 1);
        }
      )
    );
  };

  config = {
    # Wrong type: "abc" is a string, but request.value expects an int.
    contracts.arithmetic.want.consumer.instance.request.value = "abc";

    # Provider
    services.increment.arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment = config.services.increment.arithmetic;
    contracts.arithmetic.defaultProviderName = "increment";
  };
}
