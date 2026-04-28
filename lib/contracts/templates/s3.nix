{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types) port str;
in
{
  meta = {
    description = ''
      Contract for S3-compatible object storage where a consumer
      requests a bucket and a provider supplies access credentials
      and endpoint configuration.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      bucket = mkOption {
        description = ''
          Name of the S3 bucket to provision.
        '';
        type = str;
      };
    };
    result = {
      endpoint = mkOption {
        description = ''
          URL of the S3-compatible endpoint.
        '';
        type = str;
        example = "https://s3.example.com";
      };

      port = mkOption {
        description = ''
          Port of the S3-compatible endpoint.
        '';
        type = port;
      };

      bucket = mkOption {
        description = ''
          Name of the provisioned bucket (may differ from the requested name).
        '';
        type = str;
      };

      region = mkOption {
        description = ''
          Region of the bucket.
        '';
        type = str;
        default = "us-east-1";
      };

      accessKeyIDFile = mkOption {
        description = ''
          Path to a file containing the access key ID.
        '';
        type = str;
      };

      secretAccessKeyFile = mkOption {
        description = ''
          Path to a file containing the secret access key.
        '';
        type = str;
      };
    };
  };
  behaviorTest =
    {
      name,
      providerRoot,
      extraModules ? [ ],
    }:
    {
      name = "contracts_s3_${name}";
      containers.machine =
        { config, pkgs, ... }:
        {
          imports = extraModules;

          options.test = {
            bucket = mkOption {
              type = str;
              default = "testbucket";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) bucket;
              };
            })
            {
              environment.systemPackages = [ pkgs.minio-client ];
            }
          ];
        };

      testScript =
        { containers, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          with subtest("Credential files exist"):
              machine.succeed("test -f ${result.accessKeyIDFile}")
              machine.succeed("test -f ${result.secretAccessKeyFile}")

          with subtest("Configure mc client"):
              access_key = machine.succeed("cat ${result.accessKeyIDFile}").strip()
              secret_key = machine.succeed("cat ${result.secretAccessKeyFile}").strip()
              machine.succeed(
                  "mc alias set test http://${result.endpoint}:${toString result.port}"
                  + f" {access_key} {secret_key}"
              )

          with subtest("Bucket exists"):
              buckets = machine.succeed("mc ls test/")
              print(f"Buckets: {buckets}")
              assert "${result.bucket}" in buckets, f"bucket not found: {buckets}"

          with subtest("Upload and download object"):
              machine.succeed("echo 'hello s3' > /tmp/testfile")
              machine.succeed("mc cp /tmp/testfile test/${result.bucket}/testfile")
              content = machine.succeed("mc cat test/${result.bucket}/testfile").strip()
              assert content == "hello s3", f"unexpected content: {content}"
        '';
    };
}
