{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-file-backup;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "fileBackup";
  inherit (contracts.${contract}) mkProviderType;
in
{
  options.testing.hardcoded-file-backup = mkOption {
    description = ''
      Hardcoded file backup provider for testing.
      Uses tar to create timestamped snapshots in a local directory.
    '';
    type = submodule (hardcoded-file-backup: {
      options = {
        directory = mkOption {
          description = "The directory to store backup snapshots.";
          type = str;
          default = "/var/backup/hardcoded-file-backup";
        };
        ${contract} = mkOption {
          description = ''
            Instances of the fileBackup contract.
          '';
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' =
              { name, ... }:
              let
                repoDir = "${hardcoded-file-backup.config.directory}/${name}";
              in
              {
                backupService = "hardcoded-file-backup-${name}";
                restoreScript = pkgs.writeShellScript "hardcoded-file-backup-restore-${name}" ''
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
                          ${pkgs.gnutar}/bin/tar xf "$snapshot" -C /
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
    contracts.${contract}.providers.hardcoded-file-backup.module =
      options.testing.hardcoded-file-backup;

    systemd.services =
      lib.concatMapNestedAttrs'
        (options.testing.hardcoded-file-backup.type.getSubOptions [ ]).${contract}.type
        (
          path: instance:
          let
            name = lib.concatStringsSep "_" path;
            inherit (instance) request;
            repoDir = "${cfg.directory}/${lib.concatStringsSep "/" path}";
            excludeArgs = lib.concatMapStringsSep " " (
              p: "--exclude=${lib.escapeShellArg p}"
            ) request.excludePatterns;
            sourceDirArgs = lib.concatMapStringsSep " " lib.escapeShellArg request.sourceDirectories;
          in
          {
            "hardcoded-file-backup-${name}" = {
              description = "Hardcoded file backup for ${name}";
              serviceConfig = {
                Type = "oneshot";
                User = request.user;
              };
              script = ''
                mkdir -p "${repoDir}"
                ${lib.concatMapStringsSep "\n" (h: "${h}") request.hooks.beforeBackup}
                ${pkgs.gnutar}/bin/tar cf "${repoDir}/snapshot-$(date +%s)" \
                  ${excludeArgs} ${sourceDirArgs}
                ${lib.concatMapStringsSep "\n" (h: "${h}") request.hooks.afterBackup}
              '';
            };
          }
        )
        cfg.${contract};

    system.activationScripts =
      lib.concatMapNestedAttrs'
        (options.testing.hardcoded-file-backup.type.getSubOptions [ ]).${contract}.type
        (
          path: instance:
          let
            name = lib.concatStringsSep "_" path;
            repoDir = "${cfg.directory}/${lib.concatStringsSep "/" path}";
          in
          {
            ${"hardcoded-file-backup-${name}"} = ''
              mkdir -p "${repoDir}"
              chown ${instance.request.user} "${repoDir}"
            '';
          }
        )
        cfg.${contract};
  };
}
