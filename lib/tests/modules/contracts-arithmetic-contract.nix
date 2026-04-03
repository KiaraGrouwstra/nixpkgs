# Shared module: defines the `arithmetic` contract type for use in lib-level tests.
# Wraps nixos/tests/contracts/arithmetic-contract.nix with the contracts module,
# since bare lib.evalModules contexts don't include it automatically.
{ ... }:
{
  imports = [
    ../../../nixos/modules/contracts/default.nix
    ../../../nixos/tests/contracts/arithmetic-contract.nix
  ];
}
