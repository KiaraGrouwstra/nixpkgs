{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-streaming-backup;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "streamingBackup";
  inherit (contracts.${contract}) mkProviderType;
in
{
  options.testing.hardcoded-streaming-backup = mkOption {
    description = ''
      Hardcoded streaming backup provider for testing.
      Stores streaming output in timestamped files and replays on restore.
    '';
    type = submodule (hardcoded-streaming-backup: {
      options = {
        directory = mkOption {
          description = "The directory to store backup data.";
          type = str;
          default = "/var/backup/hardcoded-streaming-backup";
        };
        ${contract} = mkOption {
          description = ''
            Instances of the streamingBackup contract.
          '';
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' =
              { name, request }:
              let
                repoDir = "${hardcoded-streaming-backup.config.directory}/${name}";
              in
              {
                backupService = "hardcoded-streaming-backup-${name}";
                restoreScript = pkgs.writeShellScript "hardcoded-streaming-backup-restore-${name}" ''
                  set -euo pipefail
                  case "''${1:-}" in
                    snapshots)
                      ls -1 "${repoDir}"/snapshot-* 2>/dev/null || echo "No snapshots found."
                      ;;
                    restore)
                      shift
                      case "''${1:-}" in
                        latest)
                          snapshot=$(ls -1d "${repoDir}"/snapshot-* 2>/dev/null | sort | tail -1)
                          if [ -z "$snapshot" ]; then
                            echo "No snapshots found." >&2
                            exit 1
                          fi
                          cat "$snapshot" | ${request.restoreCmd}
                          ;;
                        *)
                          echo "Usage: $0 restore latest" >&2; exit 1
                          ;;
                      esac
                      ;;
                    *)
                      echo "Usage: $0 {snapshots|restore latest}" >&2; exit 1
                      ;;
                  esac
                '';
              };
          };
        };
      };
    });
  };

  config = {
    contracts.${contract}.providers.hardcoded-streaming-backup.module =
      options.testing.hardcoded-streaming-backup;

    systemd.services =
      lib.concatMapNestedAttrs'
        (options.testing.hardcoded-streaming-backup.type.getSubOptions [ ]).${contract}.type
        (
          path: instance:
          let
            name = lib.concatStringsSep "_" path;
            inherit (instance) request;
            repoDir = "${cfg.directory}/${lib.concatStringsSep "/" path}";
          in
          {
            "hardcoded-streaming-backup-${name}" = {
              description = "Hardcoded streaming backup for ${name}";
              serviceConfig.Type = "oneshot";
              script = ''
                mkdir -p "${repoDir}"
                ${request.backupCmd} > "${repoDir}/snapshot-$(date +%s)"
              '';
            };
          }
        )
        cfg.${contract};

    system.activationScripts =
      lib.concatMapNestedAttrs'
        (options.testing.hardcoded-streaming-backup.type.getSubOptions [ ]).${contract}.type
        (
          path: _instance:
          let
            name = lib.concatStringsSep "_" path;
            repoDir = "${cfg.directory}/${lib.concatStringsSep "/" path}";
          in
          {
            ${"hardcoded-streaming-backup-${name}"} = ''
              mkdir -p "${repoDir}"
            '';
          }
        )
        cfg.${contract};
  };
}
