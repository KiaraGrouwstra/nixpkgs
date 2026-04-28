{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.sso.behaviorTest {
  name = "hardcoded-sso";
  providerRoot = [
    "testing"
    "hardcoded-sso"
    "sso"
    "myapp"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-sso.nix
    (
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.curl ];
        contracts.sso.defaultProviderName = "hardcoded-sso";
        # Relax sandboxing for nspawn containers.
        systemd.services.dex.serviceConfig = {
          PrivateUsers = lib.mkForce false;
          DynamicUser = lib.mkForce false;
          MemoryDenyWriteExecute = lib.mkForce false;
          SystemCallFilter = lib.mkForce [ ];
          BindReadOnlyPaths = lib.mkForce [ ];
          BindPaths = lib.mkForce [ ];
          StateDirectory = "dex";
        };
        users.users.dex = {
          isSystemUser = true;
          group = "dex";
        };
        users.groups.dex = { };
      }
    )
  ];
}
