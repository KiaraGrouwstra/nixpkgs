{ pkgs, lib, ... }:

# Upgrades a working Mastodon instance and checks the two-phase migration:
# the pre-deploy pass has to finish before the new code starts serving, and the
# post-deploy pass only afterwards. Also checks that the "at least one deploy
# per minor release series" rule upstream documents is enforced.

let
  oldVersion = pkgs.mastodon.version;
  parts = lib.splitVersion oldVersion;
  series =
    offset: "${builtins.elemAt parts 0}.${toString (lib.toInt (builtins.elemAt parts 1) + offset)}.0";

  # The next minor series, which is a supported upgrade.
  newVersion = series 1;
  # Two series beyond that, so that once the upgrade above has been deployed
  # this one skips a whole series and must be refused.
  tooFarVersion = series 3;

  # Only `passthru.version` differs, so the derivation is untouched and Mastodon
  # itself is not rebuilt. What changes is the migration runner, which embeds
  # the target version.
  bump =
    version:
    pkgs.mastodon.overrideAttrs (old: {
      passthru = old.passthru // {
        inherit version;
      };
    });
in
{
  name = "mastodon-upgrade";
  meta.maintainers = [ ];

  nodes.server = {
    services.mastodon = {
      enable = true;
      configureNginx = false;
      localDomain = "mastodon.local";
      enableUnixSocket = false;
      streamingProcesses = 1;
      smtp = {
        createLocally = false;
        fromAddress = "mastodon@mastodon.local";
      };
      # Without an allowlist, creating an account tries to resolve the address
      # domain, which the test VM cannot do.
      extraConfig.EMAIL_DOMAIN_ALLOWLIST = "example.com";
    };

    specialisation = {
      upgraded.configuration.services.mastodon.package = bump newVersion;
      skipping.configuration.services.mastodon.package = bump tooFarVersion;
    };

    virtualisation.memorySize = 3072;
  };

  testScript = ''
    PRE = "mastodon-migrate-pre.service"
    POST = "mastodon-migrate-post.service"
    WEB = "mastodon-web.service"
    STAMP = "/var/lib/mastodon/.nixos-state-migration"


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
        # For the oneshots that is when the migration script exited.
        return int(
            server.succeed(f"systemctl show -p ActiveEnterTimestampMonotonic --value {unit}").strip()
        )


    def accounts() -> str:
        return server.succeed(
            "runuser -u postgres -- psql -d mastodon -tAc"
            " \"select username from accounts where username = 'bob'\""
        ).strip()


    def is_serving() -> None:
        server.wait_for_open_port(55001, timeout=600)
        server.succeed(
            "curl --fail -H 'Host: mastodon.local' http://localhost:55001/api/v1/instance"
        )


    server.wait_for_unit(PRE, timeout=600)
    server.wait_for_unit(WEB, timeout=600)
    server.wait_for_unit("mastodon-sidekiq-all.service", timeout=600)
    is_serving()

    with subtest("the fresh installation is seeded and stamped"):
        t.assertEqual(stamp(), {"version": "${oldVersion}", "phase": "complete"})
        t.assertIn("fresh installation, initialising at version ${oldVersion}", unit_log(PRE))
        # Nothing to do post-deploy when there was no upgrade.
        server.wait_for_unit(POST, timeout=600)
        t.assertIn("state is already at version ${oldVersion}", unit_log(POST))
        server.succeed("mastodon-tootctl accounts create bob --email=bob@example.com")
        t.assertEqual(accounts(), "bob")

    with subtest("upgrading brackets the restart with the two migration phases"):
        server.succeed(
            "/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test"
        )
        t.assertIn("migrating from ${oldVersion} to ${newVersion}", unit_log(PRE))
        t.assertIn(
            "running post-deploy migrations from ${oldVersion} to ${newVersion}", unit_log(POST)
        )
        t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
        # Ordering of the start jobs, which is what the mechanism guarantees.
        # It says nothing about the web process being ready, only about the
        # unit having been started, which is all the post phase requires.
        t.assertLess(activated(PRE), started(WEB))
        t.assertLess(activated(WEB), started(POST))

    with subtest("the upgraded instance still serves the data it had"):
        is_serving()
        t.assertEqual(accounts(), "bob")

    with subtest("skipping a minor release series is refused"):
        server.fail("/run/booted-system/specialisation/skipping/bin/switch-to-configuration test")
        server.succeed(f"systemctl is-failed {PRE}")
        t.assertIn(
            "refusing to upgrade from ${newVersion} to ${tooFarVersion}:"
            " at least one minor release series is skipped",
            unit_log(PRE),
        )
        # The refusal must not have rewritten the record of what is on disk.
        t.assertEqual(stamp(), {"version": "${newVersion}", "phase": "complete"})
        server.fail(f"systemctl is-active {WEB}")

    with subtest("redeploying the version on disk recovers"):
        server.succeed(
            "/run/booted-system/specialisation/upgraded/bin/switch-to-configuration test"
        )
        server.wait_for_unit(WEB, timeout=600)
        is_serving()
        t.assertEqual(accounts(), "bob")
  '';
}
