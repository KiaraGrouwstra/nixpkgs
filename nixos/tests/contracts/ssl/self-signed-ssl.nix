{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.ssl.behaviorTest {
  name = "self-signed-ssl";
  providerRoot = [
    "testing"
    "self-signed-ssl"
    "ssl"
    "mycert"
  ];
  extraModules = [
    ../../../modules/testing/self-signed-ssl.nix
    (
      { pkgs, ... }:
      {
        contracts.ssl.defaultProviderName = "self-signed-ssl";
        environment.systemPackages = [ pkgs.openssl ];
      }
    )
  ];
}
