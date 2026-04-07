{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    listOf
    nonEmptyListOf
    path
    str
    submodule
    ;
in
{
  meta = {
    description = ''
      Contract for file backup where a directory containing
      regular files is to be backed up.
    '';
    maintainers = with lib.maintainers; [
      kiara
    ];
  };
  interface = {
    request = {
      user = mkOption {
        description = ''
          Unix user doing the backups.
        '';
        type = str;
        example = "vaultwarden";
      };

      sourceDirectories = mkOption {
        description = ''
          Directories to back up.
        '';
        type = nonEmptyListOf str;
        example = [ "/var/lib/vaultwarden" ];
      };

      excludePatterns = mkOption {
        description = ''
          File patterns to exclude.
        '';
        type = listOf str;
        default = [ ];
      };

      hooks = mkOption {
        description = ''
          Hooks to run around the backup.
        '';
        default = { };
        type = submodule {
          options = {
            beforeBackup = mkOption {
              description = ''
                Hooks to run before backup.
              '';
              type = listOf path;
              default = [ ];
            };

            afterBackup = mkOption {
              description = ''
                Hooks to run after backup.
              '';
              type = listOf path;
              default = [ ];
            };
          };
        };
      };
    };
    result = {
      restoreScript = mkOption {
        description = ''
          Path to a script that can restore the backed up files.
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
      name = "contracts_filebackup_${name}";
      nodes.machine =
        { config, ... }:
        {
          imports = extraModules;

          options.test = {
            username = mkOption {
              type = str;
              default = "testuser";
            };

            sourceDirectories = mkOption {
              type = listOf str;
              default = [
                "/srv/test-files/A"
                "/srv/test-files/B"
              ];
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) sourceDirectories;
                user = config.test.username;
              };
            })
            (lib.mkIf (config.test.username != "root") {
              users.users.${config.test.username} = {
                isSystemUser = true;
                group = config.test.username;
              };
              users.groups.${config.test.username} = { };
            })
          ];
        };

      testScript =
        { nodes, ... }:
        let
          cfg = nodes.machine;
          inherit (lib.getAttrFromPath providerRoot nodes.machine) result;
        in
        ''
          username = "${cfg.test.username}"
          sourceDirectories = [ ${lib.concatMapStringsSep ", " (x: ''"${x}"'') cfg.test.sourceDirectories} ]

          def list_files(dir):
              files = {}
              out = machine.succeed(f"find {dir} -type f").strip()
              if not out:
                  return files
              for f in out.split("\n"):
                  content = machine.succeed(f"cat {f}").strip()
                  files[f] = content
              return files

          with subtest("Create initial content"):
              for path in sourceDirectories:
                  machine.succeed(f"""
                      mkdir -p {path}
                      echo fileA_v1 > {path}/fileA
                      echo fileB_v1 > {path}/fileB
                      chown -R {username}: {path}
                      chmod -R go-rwx {path}
                  """)

              for path in sourceDirectories:
                  files = list_files(path)
                  assert files[f"{path}/fileA"] == "fileA_v1", f"unexpected fileA: {files}"
                  assert files[f"{path}/fileB"] == "fileB_v1", f"unexpected fileB: {files}"

          with subtest("First backup"):
              machine.succeed("systemctl start ${result.backupService}")

          with subtest("Modify content"):
              for path in sourceDirectories:
                  machine.succeed(f"""
                      echo fileA_v2 > {path}/fileA
                      echo fileB_v2 > {path}/fileB
                  """)

          with subtest("Delete content"):
              for path in sourceDirectories:
                  machine.succeed(f"rm -rf {path}/*")
                  assert len(list_files(path)) == 0, "files should be deleted"

          with subtest("Restore from backup"):
              machine.succeed("${result.restoreScript} restore latest")

              for path in sourceDirectories:
                  files = list_files(path)
                  assert files[f"{path}/fileA"] == "fileA_v1", f"restore failed for fileA: {files}"
                  assert files[f"{path}/fileB"] == "fileB_v1", f"restore failed for fileB: {files}"
        '';
    };
}
