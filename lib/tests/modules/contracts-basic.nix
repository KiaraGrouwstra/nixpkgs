{ lib, ... }:
{
  imports = [ lib.contract.module ];

  contractDefinitions.arithmetic = {
    meta = {
      description = "Dummy arithmetic contract for tests.";
      maintainers = [ ];
    };
    interface = {
      request.value = lib.mkOption { type = lib.types.int; };
      result.value = lib.mkOption { type = lib.types.int; };
    };
  };

  contracts.arithmetic.want.consumer.x = {
    request.value = 5;
    result.value = 6;
  };
}
