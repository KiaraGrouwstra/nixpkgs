# Non-module dependencies (`importApply`)
{
  formats,
  runCommand,
}:

# Service module
{
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.vector;
  format = formats.toml { };
in
{
  _class = "service";
  options.vector = {
    package = lib.mkPackageOption null "vector" { };

    journaldAccess = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Vector to access journald.";
    };

    gracefulShutdownLimitSecs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = ''
        Duration in seconds to wait for graceful shutdown after SIGINT or
        SIGTERM. After this, Vector will force shutdown.
      '';
    };

    validateConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Check the vector config during build time. Disable when
        interpolating environment variables.
      '';
    };

    settings = lib.mkOption {
      type = (formats.json { }).type;
      default = { };
      description = "Vector configuration in Nix.";
    };
  };

  config =
    let
      conf = format.generate "vector.toml" cfg.settings;
      validatedConfig =
        runCommand "validate-vector-conf"
          { nativeBuildInputs = [ cfg.package ]; }
          ''
            vector validate --no-environment "${conf}"
            ln -s "${conf}" "$out"
          '';
      configFile = if cfg.validateConfig then validatedConfig else conf;
    in
    {
      process = {
        argv = [
          (lib.getExe cfg.package)
          "--config"
          configFile
          "--graceful-shutdown-limit-secs"
          (toString cfg.gracefulShutdownLimitSecs)
        ];
        directories.state = "vector";
        capabilities = [ "net_bind_service" ];
        reload.signal = "SIGHUP";
      };

      configData."vector.toml" = {
        source = configFile;
      };
    }
    # Systemd-specific refinements
    // lib.optionalAttrs (options ? systemd) {
      systemd.service = {
        after = [ "network-online.target" ];
        requires = [ "network-online.target" ];
        serviceConfig = {
          DynamicUser = true;
          SupplementaryGroups = lib.mkIf cfg.journaldAccess "systemd-journal";
        };
        unitConfig = {
          StartLimitIntervalSec = 10;
          StartLimitBurst = 5;
        };
      };
    };
}
