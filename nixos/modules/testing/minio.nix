{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.minio;

  inherit (lib)
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "s3";
  providerName = "minio";
  inherit (config.contracts.${contract}) mkProviderType;

  accessKey = "minioadmin";
  secretKey = "minioadmin";
in
{
  # The contract provider option reads `config.contracts` for its
  # `type`/`default`, which cannot be evaluated in the sandboxed split options
  # doc build. Document it in the eager build instead.
  meta.buildDocsInSandbox = false;

  options.testing.minio = mkOption {
    description = ''
      MinIO reference provider for the `s3` contract, for testing.
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
          default = "/run/minio";
        };
        ${contract} = mkOption {
          description = "Instances of the s3 contract.";
          default = config.contracts.${contract}.providerRequests.${providerName};
          defaultText = lib.literalExpression "config.contracts.${contract}.providerRequests.${providerName}";
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
    contracts.${contract}.providers.minio.module = options.testing.minio;

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

    system.activationScripts.minio-credentials = ''
      mkdir -p "${cfg.credentialsDir}"
      echo "${accessKey}" > "${cfg.credentialsDir}/access-key-id"
      echo "${secretKey}" > "${cfg.credentialsDir}/secret-access-key"
      cat > "${cfg.credentialsDir}/minio-root" <<EOF
      MINIO_ROOT_USER=${accessKey}
      MINIO_ROOT_PASSWORD=${secretKey}
      EOF
      chmod 0400 "${cfg.credentialsDir}"/access-key-id "${cfg.credentialsDir}"/secret-access-key "${cfg.credentialsDir}"/minio-root
    '';

    systemd.services.minio-buckets = {
      description = "Create S3 buckets for minio provider";
      after = [ "minio.service" ];
      # Gate `multi-user.target` on bucket provisioning so consumers (and the
      # contract test, which only waits for the target / the open port) cannot
      # observe the endpoint before its buckets exist.
      requiredBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "minio-mc";
        Environment = "HOME=/var/lib/minio-mc";
      };
      path = [ pkgs.minio-client ];
      script =
        let
          bucketNames = lib.attrValues (
            lib.concatMapNestedAttrs' (options.testing.minio.type.getSubOptions [ ]).${contract}.type (
              path: instance: {
                ${lib.concatStringsSep "_" path} = instance.request.bucket;
              }) cfg.${contract}
          );
        in
        ''
          set -euo pipefail
          # `minio.service` reaching `active` only means the process spawned,
          # not that it has finished formatting its pool and is accepting S3
          # requests, so `mc alias set` can keep hitting connection-refused for
          # a few seconds. Retry until the endpoint is actually ready before
          # provisioning buckets.
          for i in $(seq 1 60); do
            if mc alias set local http://127.0.0.1:${toString cfg.port} ${accessKey} ${secretKey}; then
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "minio endpoint never became ready" >&2
              exit 1
            fi
            sleep 1
          done
          ${lib.concatMapStringsSep "\n" (b: "mc mb --ignore-existing local/${b}") bucketNames}
        '';
    };
  };
}
