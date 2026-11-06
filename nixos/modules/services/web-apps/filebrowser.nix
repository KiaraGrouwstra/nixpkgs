{
  config,
  pkgs,
  lib,
  utils,
  ...
}:
let
  cfg = config.services.filebrowser;
  inherit (lib) types;
in
{
  options.services.filebrowser = lib.mkOption {
    default = { };
    description = ''
      FileBrowser, a web application to manage files and directories.
    '';

    # The options of the command line, and the options that map the settings
    # to the configuration file, are next to the package, so that a system
    # that does not use NixOS can use them too. The import by path does not
    # evaluate the package, see `pkgs.configFiles`.
    type = types.submoduleWith {
      modules = [
        ../../../../modules/generic/pkgs/by-name/fi/filebrowser/commands/filebrowser.nix
        (pkgs.configFiles (import ../../../../modules/generic/pkgs/by-name/fi/filebrowser/config-files.nix))
        .module
        (
          { config, ... }:
          {
            options = {
              enable = lib.mkEnableOption "FileBrowser";

              package = lib.mkOption {
                default = pkgs.filebrowser;
                defaultText = lib.literalExpression "pkgs.filebrowser";
              };

              user = lib.mkOption {
                type = types.str;
                default = "filebrowser";
                description = "User account under which FileBrowser runs.";
              };

              group = lib.mkOption {
                type = types.str;
                default = "filebrowser";
                description = "Group under which FileBrowser runs.";
              };

              openFirewall = lib.mkEnableOption "opening firewall ports for FileBrowser";

              # NixOS makes this directory with `CacheDirectory`.
              settings = lib.mkOption {
                type = types.submodule {
                  options.cache-dir = lib.mkOption {
                    default = "/var/cache/filebrowser";
                    description = ''
                      The directory where FileBrowser stores its cache.
                    '';
                    type = types.path;
                    readOnly = true;
                  };
                };
              };
            };

            config.portable.flags.config = config.portable.files."config.json".source;
          }
        )
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.filebrowser = {
        after = [ "network.target" ];
        description = "FileBrowser";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = utils.escapeSystemdExecArgs cfg.portable.argv;

          StateDirectory = "filebrowser";
          CacheDirectory = "filebrowser";
          WorkingDirectory = cfg.settings.root;

          User = cfg.user;
          Group = cfg.group;
          UMask = "0077";

          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          DevicePolicy = "closed";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
        };
      };

      tmpfiles.settings.filebrowser = {
        "${cfg.settings.root}".d = {
          inherit (cfg) user group;
          mode = "0700";
        };
        "${cfg.settings.cache-dir}".d = {
          inherit (cfg) user group;
          mode = "0700";
        };
        "${dirOf cfg.settings.database}".d = {
          inherit (cfg) user group;
          mode = "0700";
        };
      };
    };

    users.users = lib.mkIf (cfg.user == "filebrowser") {
      filebrowser = {
        inherit (cfg) group;
        isSystemUser = true;
      };
    };

    users.groups = lib.mkIf (cfg.group == "filebrowser") {
      filebrowser = { };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.settings.port ];
  };

  meta.maintainers = [
    lib.maintainers.lukaswrz
  ];
}
