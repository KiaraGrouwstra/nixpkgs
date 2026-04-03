# Tests all provider selection mechanisms:
# - no provider: accessing results errors with a clear message
# - manual: setting `contracts.*.instances` per consumer
# - defaultProvider: setting a provider reference directly
# - defaultProviderName: selecting a provider by name (enum)
#
# Uses two providers (increment: +1, double: *2) to verify the right one is selected.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  arithmeticContractDef = {
    meta = {
      description = "Arithmetic contract for provider selection tests.";
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

  mkProvider =
    f:
    mkOption {
      type = types.nestedAttrsOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              request = mkOption {
                type =
                  (lib.evalOption (mkOption { type = lib.contract.templateType; }) arithmeticContractDef)
                  .extend.request
                    { };
              };
              result = mkOption {
                type =
                  (lib.evalOption (mkOption { type = lib.contract.templateType; }) arithmeticContractDef)
                  .extend.result
                    { };
              };
            };
            config.result.value = lib.mkDefault (f config.request.value);
          }
        )
      );
    };
in
{
  imports = [ ../../contracts/module.nix ];

  options.meta = mkOption {
    type = types.attrs;
    default = { };
  };

  # Two providers with different behavior.
  options.services.increment.arithmetic = mkProvider (v: v + 1);
  options.services.double.arithmetic = mkProvider (v: v * 2);

  # Collected results for assertions.
  options.result = mkOption {
    type = types.attrsOf types.int;
  };

  config = {
    # Four contract types sharing the arithmetic interface.
    contractTypes = lib.genAttrs [ "noProvider" "manual" "byDefault" "byName" ] (
      _: arithmeticContractDef
    );

    # -- Providers: feed requests, compute results --

    services.increment.arithmetic = lib.mkMerge (
      map (ct: config.contracts.${ct}.requests) [
        "byDefault"
        "byName"
      ]
    );
    services.double.arithmetic = config.contracts.manual.requests;

    # Register providers.
    contracts.manual.providers.increment = config.services.increment.arithmetic;
    contracts.manual.providers.double = config.services.double.arithmetic;
    contracts.byDefault.providers.increment = config.services.increment.arithmetic;
    contracts.byName.providers.increment = config.services.increment.arithmetic;

    # -- Consumers: same request (value = 5) across all contract types --

    contracts.noProvider.want.consumer.instance.request.value = 5;
    contracts.manual.want.consumer.instance.request.value = 5;
    contracts.byDefault.want.consumer.instance.request.value = 5;
    contracts.byName.want.consumer.instance.request.value = 5;

    # -- Provider selection --

    # manual: per-instance override, pick "double" (5 * 2 = 10)
    contracts.manual.instances = config.contracts.manual.providers.double;

    # byDefault: set defaultProvider reference to increment (5 + 1 = 6)
    contracts.byDefault.defaultProvider = config.contracts.byDefault.providers.increment;

    # byName: set defaultProviderName to "increment" (5 + 1 = 6)
    contracts.byName.defaultProviderName = "increment";

    # -- Collect results --
    result = {
      manual = config.contracts.manual.results.consumer.instance.value;
      byDefault = config.contracts.byDefault.results.consumer.instance.value;
      byName = config.contracts.byName.results.consumer.instance.value;
    };
  };
}
