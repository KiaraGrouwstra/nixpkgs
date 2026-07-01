{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.s3.behaviorTest {
  name = "minio";
  providerRoot = [
    "testing"
    "minio"
    "s3"
    "mybucket"
  ];
  extraModules = [
    ../../../modules/testing/minio.nix
    (
      { config, ... }:
      {
        contracts.s3.defaultProvider = config.contracts.s3.providers.minio;
        services.minio.enable = true;
        # Relax sandboxing for nspawn containers.
        systemd.services.minio.serviceConfig.PrivateUsers = lib.mkForce false;
      }
    )
  ];
}
