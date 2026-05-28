{ lib, ... }:
{
  imports = [ lib.contract.module ];

  contracts.arithmetic = {
    want.value = 5;
    result.value = 6;
  };
}
