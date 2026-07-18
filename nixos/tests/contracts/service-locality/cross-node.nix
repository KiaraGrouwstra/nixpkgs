# Service-locality, cross-node: the provider is a peer on a SEPARATE node.
#
# `app` and `db` are top-level peers in ONE shared graph. The provider names its
# own node via `db.host = "db"`. A single `evalServices` resolves the whole
# graph, then the node configs partition it across TWO hosts with
# `toNixosServices`' `select` arg (the shared-eval-then-partition topology of
# `cross-node-modular-services.nix`). The app reaches the db over the network at
# hostname `db` -- a genuine cross-node boundary, not loopback.
#
# This is strictly stronger than the single-host peer case (`peer.nix`): same
# `appModule`, same peer resolution, but the endpoint now crosses a real host
# boundary.
#
# See `common.nix` for the shared contract, consumer, and provider; the consumer
# (`appModule`) is byte-identical across every locality.
{ lib, ... }:
let
  common = import ./common.nix { inherit lib; };
  inherit (common)
    sqlPort
    dbContract
    appModule
    dbProvider
    connStringFor
    serviceNode
    ;

  # `app` and `db` are top-level peers in ONE shared graph; the provider names
  # its own node via `db.host = "db"` (`toModules` accepts the list). The node
  # configs below partition this one graph across two hosts with `select`.
  services = {
    app = appModule;
    db = [
      dbProvider
      { db.host = "db"; }
    ];
  };

  connString = connStringFor services;
in
{
  name = "contracts-service-locality-cross-node";

  nodes = {
    # app node: the shared graph is resolved, but only the `app` slice is
    # emitted. The app reaches the db over the network at hostname `db` (from the
    # resolved connstring), which the VM test network resolves automatically.
    app = serviceNode {
      inherit services;
      select = [ "app" ];
    };

    # db node: the SAME shared graph resolved identically; only the `db` slice is
    # emitted. Opens 5432 so the app node can reach the listener across the
    # boundary (mirrors the HTTP test's `[ 8080 ]`).
    db =
      { pkgs, ... }:
      {
        imports = [
          (serviceNode {
            inherit services;
            select = [ "db" ];
          })
          { networking.firewall.allowedTCPPorts = [ sqlPort ]; }
        ];
      };
  };

  testScript = ''
    start_all()

    # `app` and `db` are top-level peers from one shared eval, partitioned onto
    # two hosts. The app reaches the db across the network at hostname `db`.
    db.wait_for_unit("db.service")
    db.wait_for_open_port(${toString sqlPort})
    app.wait_for_unit("app.service")
    app.wait_for_file("/run/app/connected")
    conn = app.succeed("cat /run/app/connstring").strip()
    assert conn == "${connString}", \
        f"cross-node: expected {'${connString}'!r}, got {conn!r}"
    assert conn == "postgresql://db:${toString sqlPort}/appdb", \
        f"cross-node: connection string does not name the db node: {conn!r}"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
