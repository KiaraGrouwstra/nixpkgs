{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.testing.hardcoded-sso;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "sso";
  inherit (contracts.${contract}) mkProviderType;

  clientSecret = "hardcoded-test-secret";
  issuerUrl = "http://127.0.0.1:${toString cfg.port}/dex";
in
{
  options.testing.hardcoded-sso = mkOption {
    description = ''
      Hardcoded SSO/OIDC provider for testing.
      Runs Dex with static client configuration.
    '';
    type = submodule {
      options = {
        port = mkOption {
          description = "Port for the Dex OIDC server.";
          type = lib.types.port;
          default = 5556;
        };
        secretFile = mkOption {
          description = "Path to the client secret file.";
          type = str;
          default = "/run/hardcoded-sso/client-secret";
        };
        ${contract} = mkOption {
          description = "Instances of the sso contract.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' = _: {
              issuer = issuerUrl;
              clientSecretFile = cfg.secretFile;
            };
          };
        };
      };
    };
  };

  config = {
    contracts.${contract}.providers.hardcoded-sso.module = options.testing.hardcoded-sso;

    services.dex = {
      enable = true;
      settings = {
        issuer = issuerUrl;
        storage = {
          type = "sqlite3";
          config.file = "/var/lib/dex/dex.db";
        };
        web.http = "127.0.0.1:${toString cfg.port}";
        enablePasswordDB = true;
        staticPasswords = [
          {
            email = "test@test.local";
            hash = "$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W";
            username = "test";
          }
        ];
        staticClients = lib.attrValues (
          lib.concatMapNestedAttrs' (options.testing.hardcoded-sso.type.getSubOptions [ ]).${contract}.type (
            path: instance: {
              ${lib.concatStringsSep "_" path} = {
                id = instance.request.clientID;
                name = instance.request.clientID;
                secret = clientSecret;
                redirectURIs = [ instance.request.redirectURI ];
              };
            }) cfg.${contract}
        );
      };
    };

    system.activationScripts.hardcoded-sso-secret = ''
      mkdir -p "$(dirname "${cfg.secretFile}")"
      echo "${clientSecret}" > "${cfg.secretFile}"
      chmod 0400 "${cfg.secretFile}"
    '';
  };
}
