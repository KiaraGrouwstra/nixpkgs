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
      Contract for PostgreSQL database access where a consumer requests a
      database (and optionally a role name) and a provider supplies the
      connection coordinates plus a credential.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      database = mkOption {
        description = ''
          PostgreSQL database the service requires.
          The provider is expected to create this database.
        '';
        type = str;
        example = "myapp";
      };
      username = mkOption {
        description = ''
          PostgreSQL role the service connects as. Defaults to the consumer
          name. The provider owns whether this role is a static, generate-once
          account or a short-lived one minted on demand; either way it resolves
          to the credential delivered through `passwordFile`/`urlFile`.
        '';
        type = str;
        example = "myapp";
      };
    };
    result = {
      host = mkOption {
        description = ''
          Hostname of the PostgreSQL server.
        '';
        type = str;
      };

      port = mkOption {
        description = ''
          Port of the PostgreSQL server.
        '';
        type = port;
      };

      database = mkOption {
        description = ''
          Database the consumer connects to (echoes the requested `database`).
        '';
        type = str;
      };

      username = mkOption {
        description = ''
          Role the consumer authenticates as (echoes the requested `username`).
        '';
        type = str;
      };

      passwordFile = mkOption {
        description = ''
          Path to a file containing the password for `username`. Consumers that
          configure discrete connection fields (mastodon, peertube) read this;
          consumers that want a single DSN read `urlFile` instead.
        '';
        type = str;
      };

      urlFile = mkOption {
        description = ''
          Path to a file containing the full connection DSN
          (`postgres://user:pass@host:port/db`). Consumers that take a single
          connection string (windmill, the panel's `DATABASE_URL`) load this via
          `LoadCredential`; it carries the same credential as `passwordFile`,
          just in URL form.
        '';
        type = str;
      };

      sslMode = mkOption {
        description = ''
          libpq `sslmode` consumers should use when connecting. PostgreSQL is
          internal-only and reached over TLS, so the provider serves a cert from
          the group's `ssl` provider and consumers verify against it.
        '';
        type = str;
        default = "require";
        example = "require";
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
      name = "contracts_postgresql_${name}";
      nodes.machine =
        { config, pkgs, ... }:
        {
          imports = extraModules;

          options.test = {
            database = mkOption {
              type = str;
              default = "testdb";
            };
            username = mkOption {
              type = str;
              default = "testdb";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) database username;
              };
            })
            {
              # Client tooling (`psql`) to exercise the resolved coordinates.
              environment.systemPackages = [ pkgs.postgresql ];
            }
          ];
        };

      testScript =
        { nodes, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot nodes.machine) result;
        in
        ''
          with subtest("Password file exists"):
              machine.succeed("test -f ${result.passwordFile}")

          with subtest("PostgreSQL server is reachable"):
              machine.wait_for_open_port(${toString result.port})

          with subtest("Requested database exists and the role can connect"):
              # The provisioning service creates the database + role; wait for it.
              machine.wait_until_succeeds(
                  "PGPASSWORD=$(cat ${result.passwordFile})"
                  + " psql 'host=${result.host} port=${toString result.port}"
                  + " user=${result.username} dbname=${result.database}"
                  + " sslmode=${result.sslMode}' -tAc 'SELECT current_database()'"
                  + " | grep -qw ${nodes.machine.test.database}"
              )
              output = machine.succeed(
                  "PGPASSWORD=$(cat ${result.passwordFile})"
                  + " psql 'host=${result.host} port=${toString result.port}"
                  + " user=${result.username} dbname=${result.database}"
                  + " sslmode=${result.sslMode}' -tAc '\\l'"
              )
              print(f"Database list: {output}")
        '';
    };
}
