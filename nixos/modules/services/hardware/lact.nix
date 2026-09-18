{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.lact;
  configFile = cfg.files."config.yaml";
in
{
  meta.maintainers = [ lib.maintainers.johnrtitor ];

  options.services.lact = lib.mkOption {
    default = { };
    description = ''
      LACT, a tool for monitoring, configuring and overclocking GPUs.
    '';

    # The options that map the settings to the configuration file come from the
    # package, so that a system that does not use NixOS can use them too.
    type = lib.types.submoduleWith {
      modules = [
        pkgs.lact.config.module
        {
          options = {
            enable = lib.mkEnableOption null // {
              description = ''
                Whether to enable LACT, a tool for monitoring, configuring and overclocking GPUs.

                ::: {.note}
                If you are on an AMD GPU, it is recommended to enable overdrive mode by using
                `hardware.amdgpu.overdrive.enable = true;` in your configuration.
                See [LACT wiki](https://github.com/ilya-zlobintsev/LACT/wiki/Overclocking-(AMD)) for more information.
                :::
              '';
            };

            package = lib.mkPackageOption pkgs "lact" { };
          };
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    systemd.packages = [ cfg.package ];

    environment.etc = lib.mapAttrs' (
      _name: file:
      lib.nameValuePair "lact/${file.target}" {
        inherit (file) enable source;
      }
    ) cfg.files;

    systemd.services.lactd = {
      description = "LACT GPU Control Daemon";
      wantedBy = [ "multi-user.target" ];

      # Restart when the config file changes.
      restartTriggers = lib.mkIf configFile.enable [ configFile.source ];
    };
  };
}
