{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.s3.behaviorTest {
  name = "hardcoded-s3";
  providerRoot = [
    "testing"
    "hardcoded-s3"
    "s3"
    "mybucket"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-s3.nix
    {
      contracts.s3.defaultProviderName = "hardcoded-s3";
      services.minio.enable = true;
      # Relax sandboxing for nspawn containers.
      systemd.services.minio.serviceConfig.PrivateUsers = lib.mkForce false;
    }
  ];
}
