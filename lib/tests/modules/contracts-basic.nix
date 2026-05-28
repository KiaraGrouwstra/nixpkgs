{ lib, ... }:
{
  imports = [ lib.contract.module ];

  contractDefinitions.arithmetic = {
    interface = {
      request.value = lib.mkOption { type = lib.types.int; };
      result.value = lib.mkOption { type = lib.types.int; };
    };
  };

  contracts.arithmetic = {
    want.value = 5;
    result.value = 6;
  };
}
