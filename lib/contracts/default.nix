# Functions and modules to use contracts.
# The contract types are in `./definitions`.
{ lib, ... }:
{
  # Module that routes requests from consumers to providers.
  module = ./module.nix;

  # Type of a contract type, with the options `meta`, `interface` and `mkContract`.
  definitionType = lib.types.submodule ./definition-type.nix;
}
