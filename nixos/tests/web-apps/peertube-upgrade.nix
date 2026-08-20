{ pkgs, lib, ... }:

# PeerTube migrates its own database from inside `node dist/server`, so what is
# under test here is the pair of guards around that: the dump taken before an
# upgrade, and the refusal to serve old code from data a newer release has
# already migrated.

let
  domain = "peertube.local";
  port = 9000;

  oldVersion = pkgs.peertube.version;
  parts = lib.splitVersion oldVersion;
  newVersion = "${builtins.elemAt parts 0}.${toString (lib.toInt (builtins.elemAt parts 1) + 1)}.0";

  # Only `passthru.version` differs, so the derivation is untouched and PeerTube
  # itself is not rebuilt. What changes is the migration runner, which embeds
  # the target version.
  newPeertube = pkgs.peertube.overrideAttrs (old: {
    passthru = old.passthru // {
      version = newVersion;
    };
  });
in
{
  name = "peertube-upgrade";
  meta.maintainers = [ ];

  nodes.server = {
    environment.etc."peertube/secrets-peertube".text = ''
      063d9c60d519597acef26003d5ecc32729083965d09181ef3949200cbe5f09ee
    '';

    networking.extraHosts = "127.0.0.1 ${domain}";

    services.peertube = {
      enable = true;
      localDomain = domain;
      enableWebHttps = false;
      secrets.secretsFile = "/etc/peertube/secrets-peertube";
      database.createLocally = true;
      redis.createLocally = true;
      settings.listen.hostname = "127.0.0.1";
      settings.instance.name = "PeerTube Upgrade Test";
    };

    specialisation.upgraded.configuration.services.peertube.package = newPeertube;

    virtualisation = {
      memorySize = 4096;
      cores = 2;
      diskSize = 4096;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      PRE = "peertube-migrate-pre.service"
      APP = "peertube.service"
      STAMP = "/var/lib/peertube/.nixos-state-migration"
      BACKUPS = "/var/lib/peertube/backups"
      DUMP = f"{BACKUPS}/upgrade-${newVersion}/peertube.dump"


      def unit_log(unit: str) -> str:
          # Anchored to the unit's current invocation: one journal holds every
          # phase of this test, so a plain --grep would find an earlier run.
          invocation = server.succeed(f"systemctl show -p InvocationID --value {unit}").strip()
          assert invocation, f"{unit} has no InvocationID"
          return server.succeed(f"journalctl --no-pager _SYSTEMD_INVOCATION_ID={invocation}")


      def stamp() -> dict[str, str]:
          out = server.succeed(f"cat {STAMP}").strip()
          return dict(line.split("=", 1) for line in out.splitlines())


      def started(unit: str) -> int:
          # Monotonic microseconds at which the unit's start job began.
          return int(
              server.succeed(f"systemctl show -p InactiveExitTimestampMonotonic --value {unit}").strip()
          )


      def activated(unit: str) -> int:
          # Monotonic microseconds at which systemd considered the unit started.
          # For the oneshot that is when the migration script exited.
          return int(
              server.succeed(f"systemctl show -p ActiveEnterTimestampMonotonic --value {unit}").strip()
          )


      def users() -> str:
          return server.succeed(
              "runuser -u postgres -- psql -d peertube -tAc 'select count(*) from \"user\"'"
          ).strip()


      def is_serving() -> None:
          # peertube.service is Type=simple, so it is active as soon as node has
          # forked. The open port is the first point at which it is really up.
          server.wait_for_open_port(${toString port}, timeout=600)
          server.succeed(
              "curl --fail http://${domain}:${toString port}/api/v1/config/about"
              " | grep 'PeerTube Upgrade Test'"
          )


      server.wait_for_unit(PRE, timeout=600)
      is_serving()

      with subtest("the fresh installation is stamped and not backed up"):
          t.assertEqual(stamp(), {"version": "${oldVersion}", "phase": "complete"})
          t.assertIn("fresh installation, initialising at version ${oldVersion}", unit_log(PRE))
          # The upgrade subtest below is the control proving this path can write
          # here at all, so its absence here means the backup was not taken.
          server.fail(f"test -e {BACKUPS}")
          seeded = users()
          t.assertNotEqual(seeded, "0")

      with subtest("upgrading dumps the database before the new code starts"):
          server.succeed("/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test")
          t.assertIn("migrating from ${oldVersion} to ${newVersion}", unit_log(PRE))
          t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
          # A dump of the database is as sensitive as the database, so it must not
          # be readable by anyone the data is not already visible to.
          t.assertEqual(server.succeed(f"stat -c '%U:%G %a' {DUMP}").strip(), "peertube:peertube 640")
          # A readable custom-format dump that still lists the table the row count
          # above came from, rather than merely a file that exists. Read as root,
          # since the mode asserted above is what keeps `postgres` out of it.
          listing = server.succeed(
              f"${nodes.server.services.postgresql.package}/bin/pg_restore -l {DUMP}"
          )
          t.assertIn("TABLE DATA public user peertube", listing)
          # The dump has to predate the code that migrates what it dumped.
          t.assertLess(activated(PRE), started(APP))

      with subtest("the upgraded instance still serves the data it had"):
          is_serving()
          t.assertEqual(users(), seeded)

      with subtest("going back to the older release is refused"):
          server.fail("/run/booted-system/bin/switch-to-configuration test")
          server.succeed(f"systemctl is-failed {PRE}")
          t.assertIn(
              "refusing to move from version ${newVersion} back to ${oldVersion}",
              unit_log(PRE),
          )
          # The refusal must not have rewritten the record of what is on disk.
          t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
          server.fail(f"systemctl is-active {APP}")

      with subtest("redeploying the version on disk recovers"):
          server.succeed("/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test")
          is_serving()
          t.assertEqual(users(), seeded)
    '';
}
