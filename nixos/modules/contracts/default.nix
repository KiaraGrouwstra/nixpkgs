# NixOS contracts wrapper: imports the generic `lib.contract.module` to make
# `config.contracts` available system-wide.
{ lib, ... }:
{
  imports = [ lib.contract.module ];
}
