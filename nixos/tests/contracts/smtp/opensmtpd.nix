{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.smtp.behaviorTest {
  name = "opensmtpd";
  providerRoot = [
    "testing"
    "opensmtpd"
    "smtp"
    "mymail"
  ];
  extraModules = [
    ../../../modules/testing/opensmtpd.nix
    (
      { config, ... }:
      {
        contracts.smtp.defaultProvider = config.contracts.smtp.providers.opensmtpd;
      }
    )
  ];
}
