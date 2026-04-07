{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.fileBackup.behaviorTest {
  name = "borgbackup";
  providerRoot = [
    "services"
    "borgbackup"
    "contracts"
    "fileBackup"
    "mybackup"
  ];
  extraModules = [
    ../../../modules/services/backup/borgbackup.nix
    {
      contracts.fileBackup.defaultProviderName = "borgbackup";
      services.borgbackup.contracts.fileBackup.mybackup = {
        repo = "/opt/repos/borg-repo";
        encryption.mode = "none";
        doInit = true;
      };
      system.activationScripts.borgbackup-test-setup = ''
        mkdir -p /opt/repos/borg-repo
        chmod 0777 /opt/repos/borg-repo
        chmod 0777 /opt/repos
      '';
    }
  ];
}
