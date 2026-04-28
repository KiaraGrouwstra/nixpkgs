{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.smtp.behaviorTest {
  name = "hardcoded-smtp";
  providerRoot = [
    "testing"
    "hardcoded-smtp"
    "smtp"
    "mymail"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-smtp.nix
    {
      contracts.smtp.defaultProviderName = "hardcoded-smtp";
    }
  ];
}
