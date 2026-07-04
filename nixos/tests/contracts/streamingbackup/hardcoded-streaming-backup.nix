{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.ibizaman ];
}
// lib.contracts.streamingBackup.behaviorTest {
  name = "hardcoded-streaming-backup";
  providerRoot = [
    "testing"
    "hardcoded-streaming-backup"
    "streamingBackup"
    "mystream"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-streaming-backup.nix
    (
      { config, ... }:
      {
        contracts.streamingBackup.defaultProvider =
          config.contracts.streamingBackup.providers.hardcoded-streaming-backup;
      }
    )
  ];
}
