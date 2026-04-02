{ lib, ... }:
{
  # contracts use `config` — not available in the docs build sandbox.
  meta.buildDocsInSandbox = false;
  imports = [ ../../../lib/contracts/module.nix ];
  config.contractTypes = lib.contracts;
}
