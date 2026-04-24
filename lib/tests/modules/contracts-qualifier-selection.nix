# Tests qualifier-based provider selection via `requireTags` and `providerTags`.
#
# Two providers (increment, double) are tagged differently. A consumer's
# `want` entry sets `requireTags = [ "fast" ]`, which routes that single entry
# to the matching provider and overrides the configured `defaultProvider`.
# Other entries without `requireTags` continue to use `defaultProvider`.
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
    services.increment.arithmetic = config.contracts.arithmetic.requests;
    services.double.arithmetic = config.contracts.arithmetic.requests;

    contracts.arithmetic.providers.increment.module = options.services.increment.arithmetic;
    contracts.arithmetic.providers.double.module = options.services.double.arithmetic;

    contracts.arithmetic.providerTags = {
      increment = [ "slow" ];
      double = [
        "fast"
        "cheap"
      ];
    };

    # Default provider for untagged consumers.
    contracts.arithmetic.defaultProviderName = "increment";

    # Two consumers, same request value (5).
    # - "untagged" uses the default provider (increment: 5 + 1 = 6).
    # - "tagged" requires "fast", so the double provider is selected (5 * 2 = 10),
    #   overriding the default for this single entry.
    contracts.arithmetic.want.consumer.untagged.request.value = 5;
    contracts.arithmetic.want.consumer.tagged = {
      request.value = 5;
      requireTags = [ "fast" ];
    };

    result = {
      untagged = config.contracts.arithmetic.results.consumer.untagged.value;
      tagged = config.contracts.arithmetic.results.consumer.tagged.value;
    };
  };
}
