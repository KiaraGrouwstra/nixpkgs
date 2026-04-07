{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.fileBackup.behaviorTest {
  name = "restic";
  providerRoot = [
    "services"
    "restic"
    "contracts"
    "fileBackup"
    "mybackup"
  ];
  extraModules = [
    (
      { config, ... }:
      {
        contracts.fileBackup.defaultProviderName = "restic";
        services.restic.contracts.fileBackup.mybackup = {
          repository = "/var/backup/restic-repo";
          passwordFile = "/var/backup/restic-password";
          initialize = true;
        };
        system.activationScripts.restic-test-setup = ''
          mkdir -p /var/backup
          echo "testpassword" > /var/backup/restic-password
          chmod 0400 /var/backup/restic-password
          chown -R ${config.test.username} /var/backup
        '';
      }
    )
  ];
}
