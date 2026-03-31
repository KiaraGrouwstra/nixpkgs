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
in
{
  imports = [ ./contracts-arithmetic-contract.nix ];

  options.services.increment.arithmetic = mkOption {
    type = types.nestedAttrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            request = mkOption {
              type = types.submodule {
                options.value = mkOption { type = types.int; };
              };
            };
            result = mkOption {
              default = { };
              type = types.submodule {
                options.value = mkOption {
                  type = types.int;
                  default = config.request.value + 1;
                };
              };
            };
          };
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
