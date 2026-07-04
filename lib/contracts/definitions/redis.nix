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
      Contract for a Redis-compatible cache/key-value store where a consumer
      requests an isolated namespace and a provider supplies the connection
      coordinates plus the credential for that namespace's store.

      Mirrors `s3` (the capability is named after the abstract service, not the
      implementation): the in-repo provider gives each namespace its OWN valkey
      instance (`valkey@<namespace>`, its own process + port on the group's
      valkey node), whose `default`-user password is rotated by OpenBao's
      valkey-database-secrets engine. Isolation is physical (one process per
      namespace) rather than an ACL key-scope, so the consumer authenticates
      with a password only -- there is no per-namespace ACL username. The
      contract names only the capability (`redis`), so any compatible backend
      could fulfil it.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      namespace = mkOption {
        description = ''
          The consumer's logical cache identity. The provider gives this
          namespace its own isolated store (the in-repo provider: its own
          `valkey@<namespace>` instance). Also used as the OpenBao static-role
          name that rotates that instance's password.
        '';
        type = str;
        example = "mastodon";
      };
    };
    result = {
      namespace = mkOption {
        description = ''
          The namespace this result is for (echoes the request). The in-repo
          provider rotates each namespace's password under an OpenBao static
          role named after the namespace, so the consumer renders its password
          from `database/static-creds/<namespace>`; the ACL `username` is a
          constant (`app`) and so cannot identify the static role. Empty default
          for providers that do not key a secret path on the namespace.
        '';
        type = str;
        default = "";
      };

      host = mkOption {
        description = ''
          Hostname of the Redis-compatible server.
        '';
        type = str;
      };

      port = mkOption {
        description = ''
          Port of the Redis-compatible server. The in-repo provider gives each
          namespace its own instance on its own port, so this is per-namespace.
        '';
        type = port;
      };

      username = mkOption {
        description = ''
          ACL username the consumer authenticates as, if the provider scopes
          access by ACL user. Empty (the default) means password-only auth on
          the server's built-in `default` user -- the in-repo provider isolates
          by per-namespace instance, not by ACL, so it leaves this empty.
        '';
        type = str;
        default = "";
        example = "mastodon";
      };

      passwordFile = mkOption {
        description = ''
          Path to a file containing the password. Rendered out of band by a
          secret provider (the openbao-agent renders the OpenBao-rotated
          password here). Must not live under `/nix/store` -- the peertube
          module asserts this, and the value rotates.
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
      name = "contracts_redis_${name}";
      nodes.machine =
        { config, pkgs, ... }:
        {
          imports = extraModules;

          options.test = {
            namespace = mkOption {
              type = str;
              default = "testns";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) namespace;
              };
            })
            {
              environment.systemPackages = [ pkgs.valkey ];
            }
          ];
        };

      testScript =
        { nodes, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot nodes.machine) result;
          ns = nodes.machine.test.namespace;
          cli = "valkey-cli -h ${result.host} -p ${toString result.port}";
          # Password-only auth on the instance's `default` user when the provider
          # supplies no ACL username (the in-repo per-instance provider); fall back
          # to `--user` auth if a username is present (an ACL-scoping provider).
          userArg = lib.optionalString (result.username != "") "--user ${result.username} ";
        in
        ''
          machine.wait_for_unit("multi-user.target")

          with subtest("Password file exists"):
              machine.wait_for_file("${result.passwordFile}")

          with subtest("Server is reachable"):
              machine.wait_for_open_port(${toString result.port})

          # Authenticate to the namespace's own instance with the rendered password.
          auth = "${userArg}--pass \"$(cat ${result.passwordFile})\""

          with subtest("Authenticated PING succeeds"):
              machine.succeed(f"${cli} {auth} PING")

          with subtest("SET/GET on the namespace's instance is allowed"):
              machine.succeed(f"${cli} {auth} SET ${ns}:key1 hello")
              value = machine.succeed(f"${cli} {auth} GET ${ns}:key1").strip()
              assert value == "hello", f"unexpected value: {value}"

          with subtest("Wrong password is rejected"):
              # Isolation is physical (this instance serves only this namespace),
              # so the auth boundary is the password, not an ACL key-scope.
              rc, out = machine.execute("${cli} ${userArg}--pass wrongpassword PING")
              assert rc != 0 or "WRONGPASS" in out or "NOAUTH" in out, (
                  f"expected auth failure for wrong password, got rc={rc}: {out}"
              )
        '';
    };
}
