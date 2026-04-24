# Tests multi-binding: a single `want` entry fulfilled by every registered
# provider, surfaced as `allResults.<consumer>.<instance>.<provider>`.
#
# Two providers (increment: +1, double: *2) both fulfill the same request;
# `allResults` exposes both results side-by-side without one winning over
# the other. `results` continues to reflect the single selected provider.
{
  lib,
  config,
  options,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.contractTypes.arithmetic) mkProviderType;
in
{
  imports = [ ./contracts-arithmetic-contract.nix ];

  options.services.increment.arithmetic = mkOption {
    type = mkProviderType {
      fulfill =
        { value }:
        {
          value = value + 1;
        };
    };
  };
  options.services.double.arithmetic = mkOption {
    type = mkProviderType {
      fulfill =
        { value }:
        {
          value = value * 2;
        };
    };
  };

  options.result = mkOption {
    type = types.attrsOf types.int;
  };

  config = {
    contracts.arithmetic.want.consumer.op.request.value = 5;

    services.increment.arithmetic = config.contracts.arithmetic.requests;
    services.double.arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment.module = options.services.increment.arithmetic;
    contracts.arithmetic.providers.double.module = options.services.double.arithmetic;

    # Single-binding still works: pick "increment" as the default.
    contracts.arithmetic.defaultProviderName = "increment";

    result = {
      single = config.contracts.arithmetic.results.consumer.op.value;
      multiIncrement = config.contracts.arithmetic.allResults.consumer.op.increment.value;
      multiDouble = config.contracts.arithmetic.allResults.consumer.op.double.value;
    };
  };
}
