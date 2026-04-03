# Tests contracts where both the consumer and provider are modular services.
#
# - A consumer modular service declares a request via `contracts.arithmetic.want`
#   and reads results from `config.contracts.arithmetic.results`.
# - `nixos-contracts-bridge` automatically wires `contracts.<type>.want` → NixOS
#   `contracts.<type>.want`.
# - A provider modular service reads `config.contracts.arithmetic.requests` and
#   sets `contracts.arithmetic.providers.increment`.
# - `nixos-contracts-bridge` automatically collects providers into NixOS
#   `contracts.arithmetic.providers`.
{ lib, pkgs, ... }:
{
  name = "contracts-modular-services";

  nodes.machine =
    { config, pkgs, lib, ... }:
    let
      inherit (lib) mkOption types;
      inherit (config.contractTypes.arithmetic) extend;

      # Base options shared by every arithmetic contract instance (request + result).
      # Reused in both the consumer option type and the provider option type.
      arithmeticInstanceModule = {
        options = {
          request = mkOption { type = extend.request { }; };
          result = mkOption { default = { }; type = extend.result { }; };
        };
      };

      # Consumer service module.
      # Uses `contracts.arithmetic.want` to register contract requests;
      # reads results from `config.contracts.arithmetic.results`.
      consumerModule =
        {
          lib,
          config,
          name,
          ...
        }:
        {
          _class = "service";
          options.consumer.operation = mkOption {
            default = { };
            type = types.submodule arithmeticInstanceModule;
          };
          config = {
            consumer.operation.request.value = 5;
            contracts.arithmetic.want.consumer.${name} = {
              inherit (config.consumer) operation;
            };
            consumer.operation.result =
              config.contracts.arithmetic.results.consumer.${name}.operation;
            process.argv = [ "${pkgs.coreutils}/bin/true" ];
          };
        };

      # Increment contract provider implemented as a modular service.
      # Reads `config.contracts.arithmetic.requests`
      # and sets `contracts.arithmetic.providers.increment`.
      incrementProviderModule =
        {
          lib,
          config,
          ...
        }:
        {
          _class = "service";
          options.arithmetic = mkOption {
            description = "Arithmetic contract instances fulfilled by this increment provider.";
            type = types.nestedAttrsOf (
              types.submodule [
                arithmeticInstanceModule
                (
                  { config, ... }:
                  {
                    # result.value is a dynamic default that depends on the same instance's request.value.
                    # Cannot be expressed as a static override to extend.result, so set as module config.
                    config.result.value = lib.mkDefault (config.request.value + 1);
                  }
                )
              ]
            );
          };
          config = {
            arithmetic = config.contracts.arithmetic.requests;
            contracts.arithmetic.providers.increment = config.arithmetic;
            process.argv = [ "${pkgs.coreutils}/bin/true" ];
          };
        };
    in
    {
      imports = [
        # The arithmetic contract type: defined inline (not in `lib/contracts/`) to demonstrate
        # the downstream user pattern of declaring contracts in `config.contractTypes`.
        ./arithmetic-contract.nix
      ];

      # Consumer service: requests an arithmetic operation with `value = 5`.
      # `nixos-contracts-bridge` wires its `contracts.arithmetic.want` into NixOS
      # `contracts.arithmetic.want`.
      system.services.instance = {
        imports = [ consumerModule ];
      };

      # Provider service: fulfills arithmetic requests by incrementing the value.
      system.services.increment = {
        imports = [ incrementProviderModule ];
      };

      contracts.arithmetic.defaultProviderName = "increment";

      assertions = [
        {
          assertion = config.contracts.arithmetic.results.consumer.instance.operation.value == 6;
          message = "arithmetic contract: result.value should equal request.value (5) + 1 = 6";
        }
      ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
  '';

  meta.maintainers = [ ];
}
