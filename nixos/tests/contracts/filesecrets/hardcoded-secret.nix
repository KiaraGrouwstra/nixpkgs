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
    "fileSecrets"
    "testing"
    "mysecret"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    (
      { config, ... }:
      {
        # setting by defaultProvider is easier, but let's set it manually here
        contracts.fileSecrets.instances."testing"."mysecret" = config.contracts.fileSecrets.config.providers.hardcoded-secret;
        testing.hardcoded-secret.fileSecrets."testing"."mysecret".content = config.test.content;
      }
    )
  ];
}
