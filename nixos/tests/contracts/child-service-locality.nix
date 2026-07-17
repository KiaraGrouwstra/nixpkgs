# Contract-mediated service locality, entirely at the modular-service layer.
#
# A consumer service (`app`) expresses a NEED for a database via the
# `databaseConnection` contract (`contracts.databaseConnection.want.db`). It
# never names a provider, a locality, or even that a "db service" exists -- it
# owns a `want`, nothing more. A provider satisfies that `want`, and the db's
# endpoint is derived from the provider's own portable `process.ports` metadata.
#
# The whole point: the consumer (`appModule`) is byte-identical across both
# setups. Only the PROVIDER BINDING differs -- and both bindings, along with the
# contract resolution, live purely at the modular-service level via
# `lib.services.evalServices`. There is no NixOS-host layer involved in contract
# handling: this is the resolution model that also works where no host exists
# (e.g. pods in a k8s instance).
#
# Two setups, one host, same `want`:
#
#   - Co-located: the provider is the app's OWN CHILD (`app.services.db`).
#     `evalServices` lifts the child's contract participation up the ownership
#     tree, so the parent's `want` is satisfied by its child and the result
#     routes to `results.app.db`. Lowers to `app.service` + `app-db.service` on
#     one host via the systemd dash-join. Provider host is loopback.
#
#   - Distributed: the provider is a top-level PEER (`system.services.db`)
#     alongside `app` on the SAME host. `evalServices` resolves them as peers.
#     The boundary being reconfigured is between modular services, not between
#     nixos nodes -- so both stay on one host, just no longer in a parent/child
#     relation. Provider host is loopback here too.
#
# In both setups the `connectionString` is built from the provider's
# `process.ports.sql.port` metadata (5432), and the app connects to the resolved
# endpoint at runtime. The consumer's binding is identical across setups.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  portable-lib = import ../../../lib/services/lib.nix { inherit lib; };

  sqlPort = 5432;

  # --- databaseConnection contract (as in chaining.nix, inline) ---
  # request { dbName } -> result { connectionString }
  dbContract =
    { lib, ... }:
    {
      config.contractDefinitions.databaseConnection = {
        meta = {
          description = ''
            Contract for database connections where a consumer requests a named
            database and a provider returns a connection string.
          '';
          maintainers = [ ];
        };
        interface = {
          request.dbName = mkOption {
            description = "Name of the database to connect to.";
            type = types.str;
          };
          result.connectionString = mkOption {
            description = "Connection string for the database.";
            type = types.str;
          };
        };
      };
    };

  # --- CONSUMER: written ONCE, imported unchanged by both setups ---
  # Owns a `want` and reads the resolved `connectionString` into its runtime
  # config, then connects to the derived endpoint. It never owns a db, never
  # names locality, and never names a provider.
  appModule =
    { lib, config, ... }:
    {
      _class = "service";
      imports = [ dbContract ];
      options.app.db = mkOption {
        description = "Database connection for the app.";
        default.result = config.contracts.databaseConnection.results.db;
        type = config.contractDefinitions.databaseConnection.mkContract {
          request.dbName.default = "appdb";
        };
      };
      config =
        let
          connstring = config.app.db.result.connectionString;
          # Parse host/port out of `postgresql://<host>:<port>/<db>` at eval time
          # (locality-agnostic: identical logic in both setups).
          hostport = lib.head (lib.splitString "/" (lib.removePrefix "postgresql://" connstring));
          host = lib.head (lib.splitString ":" hostport);
          port = lib.last (lib.splitString ":" hostport);
        in
        {
          contracts.databaseConnection.want = { inherit (config.app) db; };
          process.directories.runtime = "app";
          # The resolved connection string flows into the service's runtime state;
          # the app then connects to the derived endpoint to prove reachability.
          # `/run/current-system/sw/bin` binaries are used because the parentless
          # `evalServices` context has no `pkgs`.
          process.argv = [
            "/run/current-system/sw/bin/sh"
            "-c"
            ''
              echo -n ${lib.escapeShellArg connstring} > /run/app/connstring
              until /run/current-system/sw/bin/nc -z ${lib.escapeShellArg host} ${lib.escapeShellArg port}; do sleep 1; done
              touch /run/app/connected
              exec sleep infinity
            ''
          ];
        };
    };

  # --- PROVIDER: databaseConnection provider ---
  # Declares `process.ports.sql.port = 5432` and builds its `connectionString`
  # result FROM that port metadata (not a hardcoded literal). The provider is
  # identical in both setups; only WHERE it is bound (child vs peer) differs.
  dbProvider =
    { lib, config, options, ... }:
    {
      _class = "service";
      imports = [ dbContract ];
      options.db.databaseConnection = mkOption {
        description = "databaseConnection instances fulfilled by this provider.";
        default = config.contracts.databaseConnection.providerRequests.db;
        type = config.contracts.databaseConnection.mkProviderType {
          fulfill =
            { dbName }:
            {
              connectionString = "postgresql://127.0.0.1:${toString config.process.ports.sql.port}/${dbName}";
            };
        };
      };
      config = {
        process.ports.sql.port = sqlPort;
        # Stand-in for a real database: keep a listener open on the declared SQL
        # port (OpenBSD nc: `-l -k <port>`, port as positional argument).
        process.argv = [
          "/run/current-system/sw/bin/sh"
          "-c"
          "exec /run/current-system/sw/bin/nc -l -k ${toString config.process.ports.sql.port}"
        ];
        contracts.databaseConnection.providers.db.module = options.db.databaseConnection;
        contracts.databaseConnection.defaultProviderName = "db";
      };
    };

  # === Setup 1: CO-LOCATED (provider is the app's OWN CHILD) =================
  # The whole `app` -- owning its `db` child provider -- is handed to
  # `evalServices`. The engine lifts the child's contract participation up the
  # ownership tree: the parent's `want` is satisfied by its child, and the
  # result routes to `results.app.db`. No hand-flattening; the contract does the
  # wiring.
  colocatedEval = portable-lib.evalServices {
    services.app = {
      imports = [ appModule ];
      services.db = dbProvider;
    };
  };
  colocatedConnString = colocatedEval.contracts.databaseConnection.results.app.db.connectionString;

  # === Setup 2: DISTRIBUTED (provider is a top-level PEER) ===================
  # Same `appModule`, but the provider is a sibling top-level service rather than
  # a child. Resolved as peers. On the same host -- the boundary is between
  # modular services, not between nixos nodes.
  distributedEval = portable-lib.evalServices {
    services = {
      app = appModule;
      db = dbProvider;
    };
  };
  distributedConnString = distributedEval.contracts.databaseConnection.results.app.db.connectionString;

in
{
  name = "contracts-child-service-locality";

  nodes = {
    # Co-located: `db` is a child sub-service of `app`, so this host runs
    # `app.service` + `app-db.service` (the systemd dash-join of the ownership
    # relation). The resolved `connectionString` from `colocatedEval` is seeded
    # into the baked `app`, since a NixOS `system.services` tree does not itself
    # run contract resolution -- that happened in `evalServices`.
    colocated =
      { pkgs, ... }:
      {
        imports = [
          dbContract
          {
            system.services.app = {
              imports = [ appModule ];
              app.db.result.connectionString = colocatedConnString;
              services.db.imports = [ dbProvider ];
            };
          }
        ];
        environment.systemPackages = [ pkgs.netcat ];
      };

    # Distributed: `app` and `db` are top-level peers on the SAME host. Same
    # `appModule`; the resolved connection string from `distributedEval` is
    # seeded in. `db` is a sibling service, not a child.
    distributed =
      { pkgs, ... }:
      {
        imports = [
          dbContract
          {
            system.services.app = {
              imports = [ appModule ];
              app.db.result.connectionString = distributedConnString;
            };
            system.services.db.imports = [ dbProvider ];
          }
        ];
        environment.systemPackages = [ pkgs.netcat ];
      };
  };

  testScript = ''
    start_all()

    # --- Co-located setup: provider is the app's child ---
    # `db` is a child of `app`, so it lowers to `app-db.service` (dash-join).
    colocated.wait_for_unit("app-db.service")
    colocated.wait_for_unit("app.service")
    # The app derived host:port from process.ports metadata and reached the db.
    colocated.wait_for_file("/run/app/connected")
    conn = colocated.succeed("cat /run/app/connstring").strip()
    assert conn == "${colocatedConnString}", \
        f"co-located: expected {'${colocatedConnString}'!r}, got {conn!r}"
    assert conn == "postgresql://127.0.0.1:${toString sqlPort}/appdb", \
        f"co-located: connection string not derived from port metadata: {conn!r}"

    # --- Distributed setup: provider is a top-level peer on the same host ---
    # `app` and `db` are independent top-level services.
    distributed.wait_for_unit("db.service")
    distributed.wait_for_unit("app.service")
    distributed.wait_for_file("/run/app/connected")
    conn2 = distributed.succeed("cat /run/app/connstring").strip()
    assert conn2 == "${distributedConnString}", \
        f"distributed: expected {'${distributedConnString}'!r}, got {conn2!r}"
    assert conn2 == "postgresql://127.0.0.1:${toString sqlPort}/appdb", \
        f"distributed: connection string not derived from port metadata: {conn2!r}"

    # --- The key invariant: the consumer's binding is identical across setups. ---
    # Both setups import the SAME `appModule` and resolve to the SAME connection
    # string. The ONLY difference is the provider binding (own child vs top-level
    # peer), which the contract abstracts over -- the consumer never encoded it.
    assert "${colocatedConnString}" == "${distributedConnString}", \
        "consumer binding differs across setups; the contract failed to abstract locality"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
