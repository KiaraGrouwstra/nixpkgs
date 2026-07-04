{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.oidc.behaviorTest {
  name = "dex";
  providerRoot = [
    "testing"
    "dex"
    "oidc"
    "myapp"
  ];
  extraModules = [
    ../../../modules/testing/dex.nix
    (
      { pkgs, config, ... }:
      {
        environment.systemPackages = [ pkgs.curl ];
        contracts.oidc.defaultProvider = config.contracts.oidc.providers.dex;
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
