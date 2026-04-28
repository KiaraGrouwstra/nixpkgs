{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.self-signed-ssl;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "ssl";
  inherit (contracts.${contract}) mkProviderType;
in
{
  options.testing.self-signed-ssl = mkOption {
    description = "Self-signed SSL certificate provider for testing.";
    type = submodule (self-signed-ssl: {
      options = {
        directory = mkOption {
          description = "Directory under which per-instance cert/key pairs are stored.";
          type = str;
          default = "/run/self-signed-ssl";
        };
        ${contract} = mkOption {
          description = "Instances of the ssl contract fulfilled by self-signed certificates.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' =
              { name, ... }:
              {
                cert = "${self-signed-ssl.config.directory}/${name}/cert.pem";
                key = "${self-signed-ssl.config.directory}/${name}/key.pem";
                systemdService = "self-signed-ssl-${name}.service";
              };
          };
        };
      };
    });
  };

  config = {
    contracts.${contract}.providers.self-signed-ssl.module = options.testing.self-signed-ssl;

    systemd.services =
      lib.concatMapNestedAttrs' (options.testing.self-signed-ssl.type.getSubOptions [ ]).${contract}.type
        (
          path: instance:
          let
            name = lib.concatStringsSep "_" path;
            inherit (instance) request result;
            certDir = builtins.dirOf result.cert;
          in
          {
            "self-signed-ssl-${name}" = {
              description = "Self-signed SSL certificate for ${request.domain}";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                if [ -f ${lib.escapeShellArg result.cert} ] && [ -f ${lib.escapeShellArg result.key} ]; then
                  exit 0
                fi
                mkdir -p ${lib.escapeShellArg certDir}
                ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 \
                  -keyout ${lib.escapeShellArg result.key} \
                  -out ${lib.escapeShellArg result.cert} \
                  -days 365 -nodes -subj "/CN=${request.domain}"
                chmod 0644 ${lib.escapeShellArg result.cert}
                chmod 0600 ${lib.escapeShellArg result.key}
              '';
            };
          }
        )
        cfg.${contract};
  };
}
