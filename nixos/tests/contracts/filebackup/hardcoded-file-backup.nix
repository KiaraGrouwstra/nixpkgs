{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.fileBackup.behaviorTest {
  name = "hardcoded-file-backup";
  providerRoot = [
    "testing"
    "hardcoded-file-backup"
    "fileBackup"
    "mybackup"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-file-backup.nix
    (
      { config, ... }:
      {
        contracts.fileBackup.defaultProvider = config.contracts.fileBackup.providers.hardcoded-file-backup;
        testing.hardcoded-file-backup.directory = "/opt/repos/hardcoded-backup";
      }
    )
  ];
}
