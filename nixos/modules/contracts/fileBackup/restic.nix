{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption;
  inherit (lib.types) attrsOf submodule;
in
{
  options.blocks.restic.contracts = mkOption {
    default = { };
    type = attrsOf (
      submodule (instance: {
        options =
          let
            inherit (config.contracts.fileBackup) input output;
          in
          {
            input = mkOption {
              type = input;
            };
            output = mkOption {
              type = output;
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
  ) config.blocks.restic.contracts;
}
