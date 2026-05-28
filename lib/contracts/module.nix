{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types) int submodule;
in
{
  options.contracts.arithmetic = mkOption {
    description = ''
      The `arithmetic` contract: a dummy single-instance contract used to
      demonstrate the consumer/fulfiller shared-eval pattern.

      Consumers set `contracts.arithmetic.want.value`.
      Fulfillers set `contracts.arithmetic.result.value`.
    '';
    default = { };
    type = submodule {
      options = {
        want = mkOption {
          description = "Consumer-set inputs for the arithmetic contract.";
          default = { };
          type = submodule {
            options.value = mkOption { type = int; };
          };
        };
        result = mkOption {
          description = "Fulfiller-set outputs for the arithmetic contract.";
          default = { };
          type = submodule {
            options.value = mkOption { type = int; };
          };
        };
      };
    };
  };
}
