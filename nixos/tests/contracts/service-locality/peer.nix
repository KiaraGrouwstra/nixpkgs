# Service-locality, single-host peer: the provider is a top-level PEER of the
# app on the SAME host.
#
# `app` and `db` are independent top-level services rather than parent/child.
# `evalServices` resolves them as peers, and `toNixosServices` bakes the result
# into `system.services.app`. Both lower onto ONE host, so the endpoint is still
# loopback -- the boundary being reconfigured is between modular services, not
# between nixos nodes. This is the intermediate step between the co-located child
# (`parent-child.nix`) and the genuine cross-node boundary (`cross-node.nix`).
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

  # `app` and `db` are top-level peers; the provider keeps the loopback default.
  services = {
    app = appModule;
    db = dbProvider;
  };

  connString = connStringFor services;
in
{
  name = "contracts-service-locality-peer";

  nodes.machine = serviceNode { inherit services; };

  testScript = ''
    start_all()

    # `app` and `db` are independent top-level services on one host.
    machine.wait_for_unit("db.service")
    machine.wait_for_unit("app.service")
    # The app derived host:port from process.ports metadata and reached the db.
    machine.wait_for_file("/run/app/connected")
    conn = machine.succeed("cat /run/app/connstring").strip()
    assert conn == "${connString}", \
        f"peer: expected {'${connString}'!r}, got {conn!r}"
    assert conn == "postgresql://127.0.0.1:${toString sqlPort}/appdb", \
        f"peer: connection string not derived from port metadata: {conn!r}"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
