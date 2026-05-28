# Defines the `arithmetic` contract type for use in contract tests.
# Importable in both NixOS modules and bare `lib.evalModules` calls
# (the latter must also import `lib.contract.module`).
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  config.contractDefinitions.arithmetic = {
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
