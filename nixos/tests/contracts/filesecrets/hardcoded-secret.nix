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
    "testing"
    "secret"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    (
      { config, ... }:
      {
        contracts.fileSecrets.defaultProvider = {
          # FIXME ensure such configuration can still be set from testing.hardcoded-secret directly as well
          hardcoded-secret = {
            directory = "/run/hardcodedsecrets";
          };
        };
        testing.hardcoded-secret = {
          instances."testing"."secret".content = config.test.content;
        };
      }
    )
  ];
}
