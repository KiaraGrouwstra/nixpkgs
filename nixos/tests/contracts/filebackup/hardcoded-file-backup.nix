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
    {
      contracts.fileBackup.defaultProviderName = "hardcoded-file-backup";
    }
  ];
}
