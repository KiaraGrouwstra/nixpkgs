{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-s3;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "s3";
  inherit (contracts.${contract}) mkProviderType;

  accessKey = "minioadmin";
  secretKey = "minioadmin";
in
{
  options.testing.hardcoded-s3 = mkOption {
    description = ''
      Hardcoded S3 provider for testing.
      Runs MinIO on localhost and provisions requested buckets.
    '';
    type = submodule {
      options = {
        port = mkOption {
          description = "Port for the MinIO S3 endpoint.";
          type = lib.types.port;
          default = 9000;
        };
        credentialsDir = mkOption {
          description = "Directory to store credential files.";
          type = str;
          default = "/run/hardcoded-s3";
        };
        ${contract} = mkOption {
          description = "Instances of the s3 contract.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill = request: {
              endpoint = "127.0.0.1";
              port = cfg.port;
              bucket = request.bucket;
              region = "us-east-1";
              accessKeyIDFile = "${cfg.credentialsDir}/access-key-id";
              secretAccessKeyFile = "${cfg.credentialsDir}/secret-access-key";
            };
          };
        };
      };
    };
  };

  config = {
    contracts.${contract}.providers.hardcoded-s3.module = options.testing.hardcoded-s3;

    services.minio = {
      enable = true;
      listenAddress = ":${toString cfg.port}";
      rootCredentialsFile = "${cfg.credentialsDir}/minio-root";
      # Bypass the upstream-marked-insecure check; this provider is for tests only.
      package = pkgs.minio.overrideAttrs (old: {
        meta = (old.meta or { }) // {
          knownVulnerabilities = [ ];
        };
      });
    };

    system.activationScripts.hardcoded-s3-credentials = ''
      mkdir -p "${cfg.credentialsDir}"
      echo "${accessKey}" > "${cfg.credentialsDir}/access-key-id"
      echo "${secretKey}" > "${cfg.credentialsDir}/secret-access-key"
      cat > "${cfg.credentialsDir}/minio-root" <<EOF
      MINIO_ROOT_USER=${accessKey}
      MINIO_ROOT_PASSWORD=${secretKey}
      EOF
      chmod 0400 "${cfg.credentialsDir}"/access-key-id "${cfg.credentialsDir}"/secret-access-key "${cfg.credentialsDir}"/minio-root
    '';

    systemd.services.hardcoded-s3-buckets = {
      description = "Create S3 buckets for hardcoded-s3 provider";
      after = [ "minio.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "hardcoded-s3-mc";
        Environment = "HOME=/var/lib/hardcoded-s3-mc";
      };
      path = [ pkgs.minio-client ];
      script =
        let
          bucketNames = lib.attrValues (
            lib.concatMapNestedAttrs' (options.testing.hardcoded-s3.type.getSubOptions [ ]).${contract}.type (
              path: instance: {
                ${lib.concatStringsSep "_" path} = instance.request.bucket;
              }) cfg.${contract}
          );
        in
        ''
          for i in $(seq 1 30); do
            mc alias set local http://127.0.0.1:${toString cfg.port} ${accessKey} ${secretKey} && break
            sleep 1
          done
          ${lib.concatMapStringsSep "\n" (b: "mc mb --ignore-existing local/${b}") bucketNames}
        '';
    };
  };
}
