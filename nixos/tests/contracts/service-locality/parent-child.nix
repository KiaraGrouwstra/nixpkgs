# Service-locality, parent-child: the provider is the app's OWN CHILD.
#
# `app.services.db` makes the provider a child sub-service of the consumer.
# `evalServices` lifts the child's contract participation up the ownership tree,
# so the parent's `want` is satisfied by its child and the result routes to
# `results.app.db`. `toNixosServices` bakes that result into `system.services`,
# and the graph lowers to `app.service` + `app-db.service` on ONE host via the
# systemd dash-join. The endpoint is loopback.
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

  # The provider is the app's own child sub-service.
  services = {
    app = {
      imports = [ appModule ];
      services.db = dbProvider;
    };
  };

  connString = connStringFor services;
in
{
  name = "contracts-service-locality-parent-child";

  nodes.machine = serviceNode { inherit services; };

  testScript = ''
    start_all()

    # `db` is a child of `app`, so it lowers to `app-db.service` (dash-join).
    machine.wait_for_unit("app-db.service")
    machine.wait_for_unit("app.service")
    # The app derived host:port from process.ports metadata and reached the db.
    machine.wait_for_file("/run/app/connected")
    conn = machine.succeed("cat /run/app/connstring").strip()
    assert conn == "${connString}", \
        f"parent-child: expected {'${connString}'!r}, got {conn!r}"
    assert conn == "postgresql://127.0.0.1:${toString sqlPort}/appdb", \
        f"parent-child: connection string not derived from port metadata: {conn!r}"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
