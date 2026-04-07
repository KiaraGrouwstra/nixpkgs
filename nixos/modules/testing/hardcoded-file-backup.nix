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
  inherit (config.contracts.${contract}) mkProviderType;
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
                script = pkgs.writeShellApplication {
                  name = "hardcoded-file-backup-${name}";
                  text = ''
                    verb="''${1:-}"
                    case "$verb" in
                      backup)
                        systemctl start --wait hardcoded-file-backup-${name}
                        ;;
                      snapshots)
                        find "${repoDir}" -maxdepth 1 -name 'snapshot-*' \
                          -exec basename {} \; | sort
                        ;;
                      restore)
                        shift
                        snapshot="''${1:?Usage: $0 restore <snapshot>}"
                        ${pkgs.gnutar}/bin/tar xf "${repoDir}/$snapshot" -C /
                        ;;
                      exec)
                        shift
                        exec ${pkgs.gnutar}/bin/tar "$@"
                        ;;
                      *)
                        echo "Usage: $0 {backup|snapshots|restore <snap>|exec <args...>}" >&2
                        exit 1
                        ;;
                    esac
                  '';
                };
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
