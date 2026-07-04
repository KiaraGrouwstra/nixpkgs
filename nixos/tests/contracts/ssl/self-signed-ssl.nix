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
      { pkgs, config, ... }:
      {
        contracts.ssl.defaultProvider = config.contracts.ssl.providers.self-signed-ssl;
        environment.systemPackages = [ pkgs.openssl ];
      }
    )
  ];
}
