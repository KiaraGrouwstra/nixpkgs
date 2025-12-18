{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    attrsOf
    listOf
    nonEmptyListOf
    nullOr
    path
    str
    submodule
    ;
in
{
  options.contracts.fileBackup.contracts.restic = mkOption {
    default = { };
    type = attrsOf (
      submodule (instance: {
        options = {
          input = mkOption {
            default = null;
            type = nullOr (submodule {
              options.user = mkOption {
                description = ''
                  Unix user doing the backups.
                '';
                type = str;
                example = "vaultwarden";
              };

              options.sourceDirectories = mkOption {
                description = "Directories to back up.";
                type = nonEmptyListOf str;
                example = "/var/lib/vaultwarden";
              };

              options.excludePatterns = mkOption {
                description = "File patterns to exclude.";
                type = listOf str;
                default = [ ];
              };

              options.hooks = mkOption {
                description = "Hooks to run around the backup.";
                default = { };
                type = submodule {
                  options = {
                    beforeBackup = mkOption {
                      description = "Hooks to run before backup.";
                      type = listOf path;
                      default = [ ];
                    };

                    afterBackup = mkOption {
                      description = "Hooks to run after backup.";
                      type = listOf path;
                      default = [ ];
                    };
                  };
                };
              };
            });
          };
          output = mkOption {
            type = nullOr (submodule {
              options.restoreScript = mkOption {
                type = path;
              };
              options.backupService = mkOption {
                type = str;
              };
            });
            default =
              let
                inherit (instance.config._module.args) name;
              in
              if lib.hasAttr name config.services.restic.backups then
                {
                  backupService = "restic-backups-${name}.service";
                  restoreScript = lib.getExe (
                    pkgs.writeShellApplication {
                      name = "restic-${name}";
                      text = ''
                        if [ "$1" = "snapshots" ]; then
                          restic-${name} snapshots
                        elif [ "$1" = "restore" ]; then
                          shift
                          restic-${name} restore "$1" --target /
                        fi
                      '';
                    }
                  );
                }
              else
                null;
          };
        };
      })
    );
  };
  config.services.restic.backups = lib.mapAttrs (
    name: instance:
    lib.mkIf (instance.input != null) (
      let
        inherit (instance) input;
        inherit (input) user hooks;
      in
      {
        inherit user;
        paths = input.sourceDirectories;
        backupPrepareCommand = lib.concatStringsSep "\n" hooks.beforeBackup;
        backupCleanupCommand = lib.concatStringsSep "\n" hooks.afterBackup;
        exclude = input.excludePatterns;
      }
    )
  ) config.contracts.fileBackup.contracts.restic;
}
