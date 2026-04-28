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
    {
      contracts.streamingBackup.defaultProviderName = "hardcoded-streaming-backup";
    }
  ];
}
