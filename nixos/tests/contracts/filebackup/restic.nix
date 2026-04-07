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
          repository = "/opt/repos/restic-repo";
          passwordFile = "/opt/repos/restic-password";
          initialize = true;
        };
        system.activationScripts.restic-test-setup = ''
          mkdir -p /opt/repos
          echo "testpassword" > /opt/repos/restic-password
          chmod 0777 /opt/repos
          chmod 0444 /opt/repos/restic-password
        '';
      }
    )
  ];
}
