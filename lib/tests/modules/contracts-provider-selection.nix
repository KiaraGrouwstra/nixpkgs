# Tests provider selection mechanisms:
# - no provider: accessing results errors with a clear message
# - byRef: `defaultProvider` reference for the default + a per-instance
#   override at one `instances` leaf (the other falls through to the default)
# - byName: `defaultProviderName` enum
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;

  arithmeticInterface = {
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
in
{
  imports = [ ./contracts-arithmetic-contract.nix ];

  options.result = mkOption {
    type = types.attrsOf types.int;
  };

  config = {
    # Additional contract types sharing the arithmetic interface.
    contractTypes = lib.genAttrs [
      "noProvider"
      "byRef"
      "byName"
    ] (_: arithmeticInterface);

    # -- Consumers --

    contracts.noProvider.want.consumer.instance.request.value = 5;
    # Two instances under one consumer so the override only touches one of them.
    contracts.byRef.want.consumer.fast.request.value = 5;
    contracts.byRef.want.consumer.slow.request.value = 5;
    contracts.byName.want.consumer.instance.request.value = 5;

    # -- Providers as raw attrsets --
    # increment: value + 1; double: value * 2

    contracts.byRef.providers.increment = {
      consumer.fast.result.value = config.contracts.byRef.want.consumer.fast.request.value + 1;
      consumer.slow.result.value = config.contracts.byRef.want.consumer.slow.request.value + 1;
    };
    contracts.byRef.providers.double.consumer.fast.result.value =
      config.contracts.byRef.want.consumer.fast.request.value * 2;
    contracts.byName.providers.increment.consumer.instance.result.value =
      config.contracts.byName.want.consumer.instance.request.value + 1;

    # -- Provider selection --

    # byRef: defaultProvider reference picks "increment" for everything
    # (so `slow` -> 6), and a per-instance override at `consumer.fast`
    # picks "double" (5 * 2 = 10). Per-leaf priority handling in `nestedAttrsOf`
    # lets the override compose against the `defaultProvider`-derived tree
    # without `recursiveUpdate`.
    contracts.byRef.defaultProvider = config.contracts.byRef.providers.increment;
    contracts.byRef.instances.consumer.fast = config.contracts.byRef.providers.double.consumer.fast;

    # byName: set defaultProviderName to "increment" (5 + 1 = 6)
    contracts.byName.defaultProviderName = "increment";

    # -- Collect results --
    result = {
      default = config.contracts.byRef.results.consumer.slow.value;
      override = config.contracts.byRef.results.consumer.fast.value;
      byName = config.contracts.byName.results.consumer.instance.value;
    };
  };
}
