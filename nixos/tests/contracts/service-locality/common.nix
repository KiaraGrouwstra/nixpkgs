# Shared building blocks for the contract-mediated service-locality tests.
#
# A consumer service (`app`) expresses a NEED for a database via the
# `databaseConnection` contract (`contracts.databaseConnection.want.db`). It
# never names a provider, a locality, or even that a "db service" exists -- it
# owns a `want`, nothing more. A provider satisfies that `want`, and the db's
# endpoint is derived from the provider's own portable `process.ports` metadata.
#
# The whole point: the consumer (`appModule`) is byte-identical across every
# locality. Only the PROVIDER BINDING differs -- and both the binding and the
# contract resolution live purely at the modular-service level. There is no
# NixOS-host layer involved in contract handling: this is the resolution model
# that also works where no host exists (e.g. pods in a k8s instance).
#
# Each locality gets its own test file (see `default.nix`); they all import this
# module for the shared contract, consumer, provider, and helpers, and differ
# only in the service graph, the nodes, and the runtime reachability check:
#
#   - parent-child.nix -- the provider is the app's OWN CHILD (`app.services.db`),
#     one host, loopback endpoint.
#   - peer.nix       -- the provider is a top-level PEER of the app on the SAME
#     host, loopback endpoint. The boundary moves from parent/child to peers,
#     but stays within one host.
#   - cross-node.nix -- `app` and `db` are top-level peers resolved by ONE shared
#     eval, then partitioned onto TWO hosts via `toNixosServices`' `select` arg.
#     The provider names its own node (`db.host = "db"`), so the app reaches the
#     db over the network -- a genuine cross-node boundary, not loopback.
#
# In every locality the `connectionString` is built from the provider's
# `process.ports.sql.port` metadata (5432), and the app connects to the resolved
# endpoint at runtime. The consumer's binding is identical throughout; only the
# endpoint HOST differs by locality, which the contract abstracts over and the
# consumer never encodes.
{ lib }:
let
  inherit (lib) mkOption types;

  portable-lib = import ../../../../lib/services/lib.nix { inherit lib; };

  # Default host at which a provider is reachable. Co-located and single-host
  # peer providers keep this (loopback under one PID-1); the cross-node provider
  # overrides `db.host` to its node name. Either way the CONSUMER never reads or
  # sets it.
  defaultHost = "127.0.0.1";

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

  # --- CONSUMER: written ONCE, used unchanged by every locality ---
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
          # (locality-agnostic: identical logic in every locality).
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
  # result FROM that port metadata (not a hardcoded literal) plus its own
  # reachable host. The host is declarative PROVIDER CONFIGURATION (`db.host`,
  # defaulting to loopback), not a curried argument: co-located and single-host
  # peer leave the default, cross-node sets `db.host` to the node name. The
  # module is identical everywhere; only `db.host` and WHERE it is bound (child
  # vs peer) differ.
  dbProvider =
    {
      lib,
      config,
      options,
      ...
    }:
    {
      _class = "service";
      imports = [ dbContract ];
      # Where this provider is reachable. Deployment configuration with a
      # loopback default; the consumer never reads or sets it.
      options.db.host = mkOption {
        description = "Host at which this database provider is reachable.";
        type = types.str;
        default = defaultHost;
      };
      options.db.databaseConnection = mkOption {
        description = "databaseConnection instances fulfilled by this provider.";
        default = config.contracts.databaseConnection.providerRequests.db;
        type = config.contracts.databaseConnection.mkProviderType {
          fulfill =
            { dbName }:
            {
              connectionString = "postgresql://${config.db.host}:${toString config.process.ports.sql.port}/${dbName}";
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

  # Resolve a service graph and return the app's resolved connection string.
  # Every test derives its expected connstring from real `evalServices` output
  # (no hand-wiring); the literal `postgresql://.../appdb` asserts in each test
  # script are the independent cross-check.
  connStringFor =
    services:
    (portable-lib.evalServices { inherit services; })
    .contracts.databaseConnection.results.app.db.connectionString;

  # A node config that lowers `services` (optionally restricted to `select`) into
  # `system.services`, imports the contract, and ships `nc`. Shared by every
  # locality's nodes.
  serviceNode =
    {
      services,
      select ? null,
    }:
    { pkgs, ... }:
    {
      imports = [ dbContract ];
      system.services = portable-lib.toNixosServices { inherit services select; };
      environment.systemPackages = [ pkgs.netcat ];
    };
in
{
  inherit
    lib
    portable-lib
    sqlPort
    dbContract
    appModule
    dbProvider
    connStringFor
    serviceNode
    ;
}
