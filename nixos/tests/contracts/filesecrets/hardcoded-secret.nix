args@{
  lib,
  config,
  pkgs,
  ...
}:
let
  test = import ./test.nix args;
in
test {
  name = "contracts-secrets-hardcoded-secret";
  provider = "hardcoded-secret";
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    (
      { config, ... }:
      {
        testing.hardcoded-secret.fileSecrets.test.providerOptions.content = config.test.content;
      }
    )
  ];
}
// {
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
