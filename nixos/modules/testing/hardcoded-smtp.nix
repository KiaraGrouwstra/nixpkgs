{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.testing.hardcoded-smtp;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "smtp";
  inherit (contracts.${contract}) mkProviderType;
in
{
  options.testing.hardcoded-smtp = mkOption {
    description = ''
      Hardcoded SMTP provider for testing.
      Runs a local opensmtpd instance that accepts mail on localhost.
    '';
    type = submodule {
      options = {
        port = mkOption {
          description = "Port for the SMTP server.";
          type = lib.types.port;
          default = 2525;
        };
        passwordFile = mkOption {
          description = "Path to the password file.";
          type = str;
          default = "/run/hardcoded-smtp/password";
        };
        ${contract} = mkOption {
          description = "Instances of the smtp contract.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' = _: {
              host = "127.0.0.1";
              port = cfg.port;
              username = "testuser";
              passwordFile = cfg.passwordFile;
            };
          };
        };
      };
    };
  };

  config = {
    contracts.${contract}.providers.hardcoded-smtp.module = options.testing.hardcoded-smtp;

    services.opensmtpd = {
      enable = true;
      serverConfiguration = ''
        listen on 127.0.0.1 port ${toString cfg.port}
        action "local" mbox
        match from any for any action "local"
      '';
    };

    system.activationScripts.hardcoded-smtp-password = ''
      mkdir -p "$(dirname "${cfg.passwordFile}")"
      echo "testpassword" > "${cfg.passwordFile}"
      chmod 0400 "${cfg.passwordFile}"
    '';
  };
}
