{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.ldap.behaviorTest {
  name = "hardcoded-ldap";
  providerRoot = [
    "testing"
    "hardcoded-ldap"
    "ldap"
    "myldap"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-ldap.nix
    {
      contracts.ldap.defaultProviderName = "hardcoded-ldap";
    }
  ];
}
