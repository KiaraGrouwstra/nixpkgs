# Tests for a contract defined directly in `config.contractTypes` (downstream user pattern),
# as opposed to contracts shipped in `lib.contracts`.
#
# The `arithmetic` contract has a request of one `int` and a result of one `int`.
# The `increment` provider fulfills it by returning `request.value + 1`.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [ ../../../nixos/modules/contracts/default.nix ];

  # meta is a NixOS-level option; provide a stub so the contracts module's
  # `meta.buildDocsInSandbox = false` is accepted in this bare evalModules context.
  options.meta = mkOption { type = types.attrs; default = { }; };

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
    # Define the arithmetic contract inline - not in lib.contracts.
    contractTypes.arithmetic = {
      meta = {
        description = "A contract for arithmetic operations, used for testing.";
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

    # Consumer: request the arithmetic contract with value = 5.
    contracts.arithmetic.want.consumer.instance.request.value = 5;

    # Provider: feed the requests in; the submodule default adds 1 automatically.
    services.increment.arithmetic = config.contracts.arithmetic.requests;
    contracts.arithmetic.providers.increment = config.services.increment.arithmetic;
    contracts.arithmetic.defaultProvider = config.contracts.arithmetic.providers.increment;
  };
}
