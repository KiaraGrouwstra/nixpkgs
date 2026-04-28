{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types) path str;
in
{
  meta = {
    description = ''
      Contract for streaming backup where what to back up comes from a stream.
      Well suited for backing up databases or tar archives.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      backupName = mkOption {
        description = ''
          Name of the backup in the repository.
        '';
        type = str;
        example = "postgresql.sql";
      };

      backupCmd = mkOption {
        description = ''
          A bash command that produces the backup data on stdout.
        '';
        type = str;
      };

      restoreCmd = mkOption {
        description = ''
          A bash command that reads the backup data on stdin and restores it.
        '';
        type = str;
      };
    };
    result = {
      restoreScript = mkOption {
        description = ''
          Path to a script that can restore from backup.
          Supports `restore latest` and `snapshots` subcommands.
        '';
        type = path;
      };

      backupService = mkOption {
        description = ''
          Name of the systemd service that performs the backup.
        '';
        type = str;
      };
    };
  };
  behaviorTest =
    {
      name,
      providerRoot,
      extraModules ? [ ],
    }:
    {
      name = "contracts_streamingbackup_${name}";
      containers.machine =
        { config, ... }:
        {
          imports = extraModules;

          options.test = {
            dataFile = mkOption {
              type = str;
              default = "/srv/testdata";
            };

            restoredFile = mkOption {
              type = str;
              default = "/srv/restored";
            };
          };

          config = lib.setAttrByPath providerRoot {
            request = {
              backupName = "test.dat";
              backupCmd = "cat ${config.test.dataFile}";
              restoreCmd = "cat > ${config.test.restoredFile}";
            };
          };
        };

      testScript =
        { containers, ... }:
        let
          cfg = containers.machine;
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          with subtest("Create test data"):
              machine.succeed("echo 'hello streaming backup' > ${cfg.test.dataFile}")

          with subtest("Run backup"):
              machine.succeed("systemctl start ${result.backupService}")

          with subtest("Delete original"):
              machine.succeed("rm ${cfg.test.dataFile}")

          with subtest("Restore from backup"):
              machine.succeed("${result.restoreScript} restore latest")

          with subtest("Verify restored data"):
              content = machine.succeed("cat ${cfg.test.restoredFile}").strip()
              assert content == "hello streaming backup", f"unexpected: {content}"
        '';
    };
}
