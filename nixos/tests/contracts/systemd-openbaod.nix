# Tests the systemd-openbaod per-service secret broker end-to-end.
#
# Sets up:
# - OpenBao server in dev mode (no TLS, root token "root")
# - an `openbao agent` (services.openbao.agents.default) authenticating with a
#   token file and rendering the templates declared by services below
# - the systemd-openbaod daemon + socket brokering those rendered secrets to the
#   consuming service via LoadCredential and EnvironmentFile
#
# Verifies that:
# - a service receives its secret both as a systemd credential (vault.secrets)
#   and through an EnvironmentFile (vault.environmentTemplate)
# - rotating the secret in OpenBao makes the agent re-render and run
#   `try-reload-or-restart` on the consumer, so it picks up the new value
# - the `envSecrets` contract provider delivers a requested variable to its unit
#   via the broker and reloads the unit when the backing secret rotates
{ lib, ... }:
{
  name = "contracts-systemd-openbaod";

  nodes.machine =
    { config, pkgs, ... }:
    {
      virtualisation.memorySize = 1024;

      environment.systemPackages = [ pkgs.openbao ];
      environment.variables = {
        BAO_ADDR = "http://127.0.0.1:8200";
        BAO_TOKEN = "root";
      };

      # OpenBao dev server - runs without init/unseal, no TLS, kv-v2 at secret/.
      systemd.services.openbao-dev = {
        description = "OpenBao Dev Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          BAO_DEV_ROOT_TOKEN_ID = "root";
          BAO_DEV_LISTEN_ADDRESS = "127.0.0.1:8200";
          HOME = "/tmp";
        };
        serviceConfig = {
          ExecStart = "${pkgs.openbao}/bin/bao server -dev";
          Restart = "on-failure";
          LimitMEMLOCK = "infinity";
        };
      };

      # Seed the secret before the agent renders it; the agent's templates use
      # exit_on_retry_failure, so it must not start against a missing secret.
      systemd.services.setup-openbao = {
        wantedBy = [ "multi-user.target" ];
        after = [ "openbao-dev.service" ];
        path = [ pkgs.openbao ];
        environment = {
          BAO_ADDR = "http://127.0.0.1:8200";
          BAO_TOKEN = "root";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          until bao status; do sleep 1; done
          bao kv put secret/my-secret foo=bar
          bao kv put secret/env-secret token=initial
        '';
      };

      # The agent authenticates with the dev root token and renders the
      # templates declared by `app` below.
      services.openbao.agents.default.settings = {
        vault.address = "http://127.0.0.1:8200";
        auto_auth.method = [
          {
            type = "token_file";
            config.token_file_path = toString (pkgs.writeText "bao-token" "root");
          }
        ];
      };
      systemd.services.openbao-agent-default = {
        after = [ "setup-openbao.service" ];
        wants = [ "setup-openbao.service" ];
      };

      # Consumer service: gets the secret both via LoadCredential (vault.secrets)
      # and via EnvironmentFile (vault.environmentTemplate). Long-running so the
      # rotation -> try-reload-or-restart path can be observed.
      systemd.services.app = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Restart = "always";
        script = ''
          cat "$CREDENTIALS_DIRECTORY/foo" > /tmp/app-cred
          printf '%s' "$SECRET_ENV" > /tmp/app-env
          exec sleep infinity
        '';
        vault = {
          template = ''
            {{ with secret "secret/my-secret" }}{{ .Data.data | toJSON }}{{ end }}
          '';
          secrets.foo = { };
          environmentTemplate = ''
            {{ with secret "secret/my-secret" }}SECRET_ENV={{ .Data.data.foo }}{{ end }}
          '';
        };
      };

      # Contract-driven consumer: request an environment variable through the
      # `envSecrets` provider rather than hand-writing a `vault.*` template. The
      # provider renders it into `env-app`'s EnvironmentFile via the same agent.
      services.systemd-openbaod.enable = true;
      contracts.envSecrets.defaultProviderName = "systemd-openbaod";
      contracts.envSecrets.want.test.token.request = {
        unit = "env-app";
        variables.TOKEN_ENV = {
          path = "secret/data/env-secret";
          field = "token";
          base64Decode = false;
        };
      };
      systemd.services.env-app = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Restart = "always";
        script = ''
          printf '%s' "$TOKEN_ENV" > /tmp/env-app-token
          exec sleep infinity
        '';
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("openbao-dev.service")
    machine.wait_for_open_port(8200)
    machine.wait_for_unit("setup-openbao.service")
    machine.wait_for_unit("openbao-agent-default.service")

    # The consumer must receive the secret as a credential and via env.
    machine.wait_for_unit("app.service")
    machine.wait_until_succeeds("grep -q bar /tmp/app-cred")
    machine.wait_until_succeeds("grep -q bar /tmp/app-env")

    # Rotate the secret: the agent re-renders and runs try-reload-or-restart on
    # the consumer, which then reports the new value.
    machine.succeed("rm -f /tmp/app-env /tmp/app-cred")
    machine.succeed("bao kv put secret/my-secret foo=rotated")
    machine.wait_until_succeeds("grep -q rotated /tmp/app-env")
    machine.wait_until_succeeds("grep -q rotated /tmp/app-cred")

    # Contract-driven consumer: the envSecrets provider delivered TOKEN_ENV to
    # env-app via the broker, and a rotation reloads the unit with the new value.
    machine.wait_for_unit("env-app.service")
    machine.wait_until_succeeds("grep -q initial /tmp/env-app-token")
    machine.succeed("rm -f /tmp/env-app-token")
    machine.succeed("bao kv put secret/env-secret token=rotated")
    machine.wait_until_succeeds("grep -q rotated /tmp/env-app-token")
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
