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
    "instances"
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
          instances.my.secret.content = config.test.content;
        };
      }
    )
  ];
}
