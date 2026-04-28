{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types) str;
in
{
  meta = {
    description = ''
      Contract for SSO via OIDC where a consumer requests single sign-on
      integration and a provider supplies the OpenID Connect endpoint
      and client credentials.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      clientID = mkOption {
        description = ''
          Client ID to register with the OIDC provider.
        '';
        type = str;
      };

      redirectURI = mkOption {
        description = ''
          Callback URI the provider should redirect to after authentication.
        '';
        type = str;
        example = "https://myapp.example.com/oauth2/callback";
      };
    };
    result = {
      issuer = mkOption {
        description = ''
          OIDC issuer URL (the provider's discovery endpoint base).
        '';
        type = str;
        example = "https://auth.example.com";
      };

      clientSecretFile = mkOption {
        description = ''
          Path to a file containing the OIDC client secret.
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
      name = "contracts_sso_${name}";
      containers.machine =
        { config, ... }:
        {
          imports = extraModules;

          options.test = {
            clientID = mkOption {
              type = str;
              default = "test-client";
            };

            redirectURI = mkOption {
              type = str;
              default = "http://localhost:8080/callback";
            };
          };

          config = lib.setAttrByPath providerRoot {
            request = {
              inherit (config.test) clientID redirectURI;
            };
          };
        };

      testScript =
        { containers, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          import json

          with subtest("Client secret file exists"):
              machine.succeed("test -f ${result.clientSecretFile}")

          with subtest("OIDC discovery endpoint responds"):
              discovery = machine.wait_until_succeeds(
                  "curl -sf ${result.issuer}/.well-known/openid-configuration"
              )
              config = json.loads(discovery)
              print(f"OIDC discovery: {json.dumps(config, indent=2)}")
              assert config["issuer"] == "${result.issuer}", (
                  f"issuer mismatch: {config['issuer']}"
              )
              assert "authorization_endpoint" in config, "missing authorization_endpoint"
              assert "token_endpoint" in config, "missing token_endpoint"
        '';
    };
}
