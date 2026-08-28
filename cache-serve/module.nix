{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nix-cache-serve;
in
{
  options.services.nix-cache-serve = {
    enable = lib.mkEnableOption "the per-file read endpoint for a Nix binary cache";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "Package providing {command}`nix-cache-serve`.";
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8088";
      description = ''
        Address to listen on. The service speaks plain HTTP and performs no
        authentication, so it expects a reverse proxy or CDN in front of it.
      '';
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.nixos.org";
      description = ''
        Binary cache to read from. It must serve `<hash>.narinfo` and the `nar/`
        paths those narinfos point at over HTTP.
      '';
    };

    maxConcurrency = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Maximum number of NARs decompressed at once. Decompression is the entire
        server-side cost of this endpoint, so this is what bounds CPU use.
        Defaults to the number of available cores.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional {manpage}`systemd.exec(5)` `EnvironmentFile`.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nix-cache-serve = {
      description = "Per-file read endpoint for a Nix binary cache";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe cfg.package)
            "--listen"
            cfg.listen
            "--upstream"
            cfg.upstream
          ]
          ++ lib.optionals (cfg.maxConcurrency != null) [
            "--max-concurrency"
            (toString cfg.maxConcurrency)
          ]
        );
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = 1;

        DynamicUser = true;
        # The service only ever reads over HTTP; it needs nothing from the host.
        CapabilityBoundingSet = [ "" ];
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
  };
}
