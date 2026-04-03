# Tests that NixOS module consumers can use varying nesting depths in `want`.
#
# The `nestedAttrsOf` type supports arbitrary depth. A consumer can organize
# its contract options flat or grouped:
#
#   want.myapp.secret              (2 layers: consumer + option)
#   want.myapp.db.primary          (3 layers: consumer + group + option)
#   want.myapp.db.caches.fast      (4 layers: consumer + group + subgroup + option)
#
# All depths coexist in the same `want` tree and the provider fulfills them all.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  arithmeticContractDef = {
    meta = {
      description = "Arithmetic contract for nested want tests.";
      maintainers = [ ];
    };
    interface = {
      request.value = mkOption {
        description = "Input value.";
        type = types.int;
      };
      result.value = mkOption {
        description = "Output value.";
        type = types.int;
      };
    };
  };

  evaluated = lib.evalOption (mkOption { type = lib.contract.templateType; }) arithmeticContractDef;
  inherit (evaluated) extend;

  instanceModule = {
    options = {
      request = mkOption { type = extend.request { }; };
      result = mkOption { type = extend.result { }; };
    };
  };

  mkIncrementProvider = mkOption {
    type = types.nestedAttrsOf (
      types.submodule [
        instanceModule
        (
          { config, ... }:
          {
            config.result.value = lib.mkDefault (config.request.value + 1);
          }
        )
      ]
    );
  };
in
{
  imports = [ ../../contracts/module.nix ];

  options.meta = mkOption {
    type = types.attrs;
    default = { };
  };

  options.services.increment.arithmetic = mkIncrementProvider;

  config = {
    contractTypes.arithmetic = arithmeticContractDef;

    # -- Consumer: varying nesting depths in want --

    # 2 layers: consumer + option (flat)
    contracts.arithmetic.want.myapp.simple.request.value = 1;

    # 3 layers: consumer + group + option
    contracts.arithmetic.want.myapp.db.primary.request.value = 10;
    contracts.arithmetic.want.myapp.db.replica.request.value = 20;

    # 4 layers: consumer + group + subgroup + option
    contracts.arithmetic.want.myapp.caches.region-a.fast.request.value = 100;
    contracts.arithmetic.want.myapp.caches.region-b.fast.request.value = 200;

    # -- Provider --
    services.increment.arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment = config.services.increment.arithmetic;
    contracts.arithmetic.defaultProviderName = "increment";

  };
}
