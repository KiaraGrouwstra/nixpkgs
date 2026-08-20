{ pkgs, lib, ... }:

# Upgrades a working Pixelfed installation to a higher version number and
# checks that the state migrations run once, in the right direction, and leave
# the instance serving.

let
  oldVersion = pkgs.pixelfed.version;
  newVersion = "9.9.9";

  # Only `passthru.version` differs, so the derivation is untouched and no
  # rebuild is needed. The unit that changes is the migration runner, which
  # embeds the target version and pulls the application units with it.
  newPixelfed = pkgs.pixelfed.overrideAttrs (old: {
    passthru = old.passthru // {
      version = newVersion;
    };
  });
in
{
  name = "pixelfed-upgrade";
  meta.maintainers = [ ];

  nodes.server = {
    services.pixelfed = {
      enable = true;
      domain = "pixelfed.local";
      nginx = { };
      secretFile = pkgs.writeText "secrets.env" ''
        # Snakeoil secret, can be any random 32-chars secret via CSPRNG.
        APP_KEY=adKK9EcY8Hcj3PLU7rzG9rJ6KKTOtYfA
      '';
      settings."FORCE_HTTPS_URLS" = false;
    };

    specialisation.upgraded.configuration.services.pixelfed.package = newPixelfed;

    # to prevent getting killed by oom
    virtualisation.memorySize = 2048;
    virtualisation.emptyDiskImages = [ 4096 ];
    swapDevices = [ { device = "/dev/vdb"; } ];

    # allows running nixos test on qemu without kvm, eg. github actions on aarch64-linux
    systemd.settings.Manager.DefaultDeviceTimeoutSec = lib.mkForce 1800;
    boot.initrd.kernelModules = [ "virtio_console" ];
  };

  testScript = ''
    import shlex

    PRE = "pixelfed-migrate-pre.service"
    STAMP = "/var/lib/pixelfed/.nixos-state-migration"


    def unit_log(unit: str) -> str:
        # Anchored to the unit's current invocation: one journal holds every
        # phase of this test, so a plain --grep would find an earlier run.
        invocation = server.succeed(f"systemctl show -p InvocationID --value {unit}").strip()
        assert invocation, f"{unit} has no InvocationID"
        return server.succeed(f"journalctl --no-pager _SYSTEMD_INVOCATION_ID={invocation}")


    def stamp() -> dict[str, str]:
        out = server.succeed(f"cat {STAMP}").strip()
        return dict(line.split("=", 1) for line in out.splitlines())


    def invocation(unit: str) -> str:
        return server.succeed(f"systemctl show -p InvocationID --value {unit}").strip()


    def query(sql: str) -> str:
        return server.succeed(
            f"runuser -u pixelfed -- mysql -N -B -D pixelfed -e {shlex.quote(sql)}"
        ).strip()


    def is_serving() -> None:
        server.wait_for_open_port(80, timeout=1800)
        server.succeed("curl --fail -H 'Host: pixelfed.local' http://localhost")


    server.wait_for_unit(PRE, timeout=1800)
    server.wait_for_unit("phpfpm-pixelfed.service", timeout=1800)
    server.wait_for_unit("nginx.service", timeout=1800)
    is_serving()

    with subtest("the fresh installation is initialised and stamped"):
        t.assertEqual(stamp(), {"version": "${oldVersion}", "phase": "complete"})
        t.assertIn("fresh installation, initialising at version ${oldVersion}", unit_log(PRE))
        # The schema really was created by onFreshInstall, not left empty.
        t.assertNotEqual(query("show tables"), "")
        server.succeed(
            "pixelfed-manage user:create --name=test --username=test"
            " --email=test@test.com --password=test"
        )
        t.assertEqual(query("select username from users"), "test")

    with subtest("redeploying the same version migrates nothing"):
        server.succeed(f"systemctl restart {PRE}")
        journal = unit_log(PRE)
        t.assertIn("state is already at version ${oldVersion}", journal)
        t.assertNotIn("migrating from", journal)
        t.assertEqual(stamp(), {"version": "${oldVersion}", "phase": "complete"})

    with subtest("upgrading runs the migrations and restarts the application"):
        before = invocation("phpfpm-pixelfed.service")
        server.succeed(
            "/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test"
        )
        # Control for the "migrates nothing" subtest above: the same log line
        # that was absent there is present here.
        t.assertIn("migrating from ${oldVersion} to ${newVersion}", unit_log(PRE))
        t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
        t.assertNotEqual(invocation("phpfpm-pixelfed.service"), before)

    with subtest("the upgraded instance still serves the data it had"):
        server.wait_for_unit("phpfpm-pixelfed.service", timeout=1800)
        is_serving()
        t.assertEqual(query("select username from users"), "test")

    with subtest("downgrading is refused and keeps the application stopped"):
        server.fail("/run/booted-system/bin/switch-to-configuration test")
        server.succeed(f"systemctl is-failed {PRE}")
        t.assertIn(
            "refusing to move from version ${newVersion} back to ${oldVersion}", unit_log(PRE)
        )
        # The refusal must not have rewritten the record of what is on disk.
        t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
        server.fail("systemctl is-active phpfpm-pixelfed.service")

    with subtest("redeploying the version on disk recovers"):
        server.succeed(
            "/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test"
        )
        server.wait_for_unit("phpfpm-pixelfed.service", timeout=1800)
        is_serving()
        t.assertEqual(query("select username from users"), "test")
  '';
}
