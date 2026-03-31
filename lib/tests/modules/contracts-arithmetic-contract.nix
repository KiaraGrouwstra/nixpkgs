# Shared module: defines the `arithmetic` contract type for use in tests.
# Imported by tests that exercise the arithmetic contract.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [ ../../../nixos/modules/contracts/default.nix ];

  config.contractTypes.arithmetic = {
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
}
