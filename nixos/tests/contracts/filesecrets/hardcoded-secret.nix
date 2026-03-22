{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.fileSecrets.behaviorTest {
  name = "hardcoded-secret";
  providerRoot = [
    "testing"
    "hardcoded-secret"
    "secrets"
    "my"
    "secret"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    (
      { config, ... }:
      {
        testing.hardcoded-secret = {
          directory = "/run/hardcodedsecrets";
          secrets.my.secret.content = config.test.content;
        };
      }
    )
  ];
}
