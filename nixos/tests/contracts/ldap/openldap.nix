{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.ldap.behaviorTest {
  name = "openldap";
  providerRoot = [
    "testing"
    "openldap"
    "ldap"
    "myldap"
  ];
  extraModules = [
    ../../../modules/testing/openldap.nix
    (
      { config, ... }:
      {
        contracts.ldap.defaultProvider = config.contracts.ldap.providers.openldap;
      }
    )
  ];
}
