{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];
}
// lib.contracts.streamingBackup.behaviorTest {
  name = "restic";
  providerRoot = [
    "services"
    "restic"
    "contracts"
    "streamingBackup"
    "mystream"
  ];
  extraModules = [
    {
      contracts.streamingBackup.defaultProviderName = "restic";
      services.restic.contracts.streamingBackup.mystream = {
        repository = "/var/backup/restic-repo";
        passwordFile = "/var/backup/restic-password";
        initialize = true;
      };
      system.activationScripts.restic-test-setup = ''
        mkdir -p /var/backup
        echo "testpassword" > /var/backup/restic-password
        chmod 0400 /var/backup/restic-password
        chown -R root /var/backup
      '';
    }
  ];
}
