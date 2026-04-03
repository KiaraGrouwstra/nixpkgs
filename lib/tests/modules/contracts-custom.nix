# Tests for a contract defined directly in `config.contractTypes` (downstream user pattern),
# as opposed to contracts shipped in `lib.contracts`.
#
# The `arithmetic` contract has a request of one `int` and a result of one `int`.
# The `increment` provider fulfills it by returning `request.value + 1`.
# Note that this is a pure operation, making contracts overkill.
# For a full-fledged contract test, see `nixos/tests/stash.nix`.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.contractTypes.arithmetic) extend;
in
{
  imports = [ ./contracts-arithmetic-contract.nix ];

  # meta is a NixOS-level option; provide a stub so the contracts module's
  # `meta.buildDocsInSandbox = false` is accepted in this bare evalModules context.
  options.meta = mkOption { type = types.attrs; default = { }; };

  options.services.increment.arithmetic = mkOption {
    type = types.nestedAttrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            request = mkOption { type = extend.request { }; };
            result = mkOption { type = extend.result { }; };
          };
          # dynamic default: result.value depends on the same instance's request.value.
          # Cannot be expressed as a static override to extend.result, so set here instead.
          config.result.value = lib.mkDefault (config.request.value + 1);
        }
      )
    );
  };

  config = {
    # Consumer: request the arithmetic contract with value = 5.
    contracts.arithmetic.want.consumer.instance.request.value = 5;

    # Provider: feed the requests in; the submodule default adds 1 automatically.
    services.increment.arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment = config.services.increment.arithmetic;
    contracts.arithmetic.defaultProvider = config.contracts.arithmetic.providers.increment;
  };
}
