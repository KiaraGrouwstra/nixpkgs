{ ... }:

# Exercises systemd.stateMigrations against a fake application whose only state
# is a data file and an append-only event log. Every assertion reads the event
# log, so a step that is expected not to run is proven absent from a log that
# another subtest shows it can be present in.

let
  stateDir = "/var/lib/fakeapp";
  events = "${stateDir}/events";
  dataFile = "${stateDir}/data";
  stamp = "${stateDir}/.nixos-state-migration";

  record = tag: "echo ${tag} >> ${events}";
in
{
  name = "state-migrations";

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      version = config.systemd.stateMigrations.fakeapp.version;
    in
    {
      systemd.tmpfiles.rules = [ "d ${stateDir} 0755 root root - -" ];

      # The application under migration. Type=notify so that "active" means
      # ready: an ordering dependency on a Type=simple unit is satisfied on
      # fork, which would make the bracketing assertions below race.
      systemd.services.fakeapp = {
        description = "Fake application ${version}";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "notify";
          NotifyAccess = "all";
          ExecStart = pkgs.writeShellScript "fakeapp-${version}" ''
            ${record "app-start-${version}"}
            ${config.systemd.package}/bin/systemd-notify --ready
            exec sleep infinity
          '';
        };
      };

      systemd.stateMigrations.fakeapp = {
        version = lib.mkDefault "1.0.0";
        stateFile = stamp;
        before = [ "fakeapp.service" ];
        backupDir = "${stateDir}/backup";

        freshInstallTest = "test ! -e ${dataFile}";
        onFreshInstall = ''
          ${record "fresh"}
          echo seeded > ${dataFile}
        '';
        onUpgrade = record "on-upgrade";
        onUpgradePost = record "on-upgrade-post";

        steps = [
          {
            version = "1.5.0";
            description = "first reshape";
            script = record "step-1.5.0-pre";
          }
          {
            version = "2.0.0";
            description = "second reshape";
            script = record "step-2.0.0-pre";
            backup = "cp ${dataFile} $BACKUP/data";
            restore = "cp $BACKUP/data ${dataFile}";
          }
          {
            version = "2.0.0";
            description = "second reshape, post-deploy half";
            phase = "post";
            script = record "step-2.0.0-post";
          }
          {
            version = "3.0.0";
            description = "third reshape";
            script = record "step-3.0.0-pre";
          }
          {
            version = "3.0.0";
            description = "third reshape, post-deploy half";
            phase = "post";
            script = record "step-3.0.0-post";
          }
        ];
      };

      specialisation = {
        v2.configuration.systemd.stateMigrations.fakeapp.version = "2.0.0";
        v3.configuration.systemd.stateMigrations.fakeapp.version = "3.0.0";

        # A step that fails after having damaged the data it backed up.
        failing.configuration.systemd.stateMigrations.fakeapp = {
          version = "4.0.0";
          steps = [
            {
              version = "4.0.0";
              description = "deliberately broken";
              script = ''
                ${record "step-4.0.0-pre"}
                echo corrupted > ${dataFile}
                exit 7
              '';
              backup = "cp ${dataFile} $BACKUP/data";
              restore = ''
                cp $BACKUP/data ${dataFile}
                ${record "restore-4.0.0"}
              '';
            }
          ];
        };

        # 3.0.0 -> 9.0.0 skips whole major release series.
        skipping.configuration.systemd.stateMigrations.fakeapp = {
          version = "9.0.0";
          maxSkip = "major";
        };

        # Control for `skipping`: the same jump without a skip limit.
        bigJump.configuration.systemd.stateMigrations.fakeapp.version = "9.0.0";
      };
    };

  testScript =
    # python
    ''
      PRE = "fakeapp-migrate-pre.service"
      POST = "fakeapp-migrate-post.service"


      def switch(name: str) -> int:
          status, out = machine.execute(
              f"/run/booted-system/specialisation/{name}/bin/switch-to-configuration switch"
          )
          print(out)
          return status


      def restart_all() -> None:
          # One transaction, so that systemctl waits for the application too.
          # Restarting the pre unit on its own bounces the application anyway,
          # via the Requires= the module installs, but asynchronously.
          machine.succeed(f"systemctl restart {PRE} fakeapp.service {POST}")


      def events() -> list[str]:
          return machine.succeed("cat ${events}").split()


      def stamp() -> dict[str, str]:
          out = machine.succeed("cat ${stamp}").strip()
          return dict(line.split("=", 1) for line in out.splitlines())


      def unit_log(unit: str) -> str:
          # Anchored to the last invocation of the unit: one journal holds every
          # phase of this test, so a plain --grep would find an earlier run.
          invocation = machine.succeed(f"systemctl show -p InvocationID --value {unit}").strip()
          assert invocation, f"{unit} has no InvocationID"
          return machine.succeed(f"journalctl --no-pager _SYSTEMD_INVOCATION_ID={invocation}")


      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("fakeapp.service")
      machine.wait_for_unit(POST)

      with subtest("fresh installation"):
          t.assertEqual(events(), ["fresh", "app-start-1.0.0"])
          t.assertEqual(stamp(), {"version": "1.0.0", "phase": "complete"})
          t.assertEqual(machine.succeed("cat ${dataFile}").strip(), "seeded")
          # No post steps are in range on a fresh install.
          t.assertIn("state is already at version 1.0.0", unit_log(POST))

      with subtest("unchanged version is a no-op"):
          before = events()
          restart_all()
          t.assertIn("state is already at version 1.0.0", unit_log(PRE))
          # Only the application restart the transaction asked for.
          t.assertEqual(events()[len(before) :], ["app-start-1.0.0"])

      with subtest("upgrade runs exactly the in-range steps, bracketing the restart"):
          before = events()
          t.assertEqual(switch("v2"), 0)
          t.assertEqual(
              events()[len(before) :],
              [
                  "step-1.5.0-pre",
                  "step-2.0.0-pre",
                  "on-upgrade",
                  "app-start-2.0.0",
                  "step-2.0.0-post",
                  "on-upgrade-post",
              ],
          )
          t.assertEqual(stamp(), {"version": "2.0.0", "phase": "complete"})

      with subtest("backup was taken"):
          t.assertEqual(machine.succeed("cat ${stateDir}/backup/2.0.0/data").strip(), "seeded")

      with subtest("re-running either phase changes nothing"):
          before = events()
          restart_all()
          machine.succeed(f"systemctl restart {POST}")
          t.assertEqual(events()[len(before) :], ["app-start-2.0.0"])
          t.assertEqual(stamp(), {"version": "2.0.0", "phase": "complete"})

      with subtest("the next upgrade skips the steps it has already passed"):
          before = events()
          t.assertEqual(switch("v3"), 0)
          t.assertEqual(
              events()[len(before) :],
              [
                  "step-3.0.0-pre",
                  "on-upgrade",
                  "app-start-3.0.0",
                  "step-3.0.0-post",
                  "on-upgrade-post",
              ],
          )
          t.assertEqual(events().count("step-1.5.0-pre"), 1)
          t.assertEqual(events().count("step-2.0.0-pre"), 1)
          t.assertEqual(events().count("step-2.0.0-post"), 1)
          t.assertEqual(stamp(), {"version": "3.0.0", "phase": "complete"})

      with subtest("a failing step is restored from its backup and stops the app"):
          before = events()
          t.assertNotEqual(switch("failing"), 0)
          t.assertEqual(events()[len(before) :], ["step-4.0.0-pre", "restore-4.0.0"])
          t.assertEqual(machine.succeed("cat ${dataFile}").strip(), "seeded")
          machine.succeed(f"systemctl is-failed {PRE}")
          machine.fail("systemctl is-active fakeapp.service")
          t.assertEqual(stamp(), {"version": "3.0.0", "phase": "complete"})

      with subtest("recovering by redeploying the version that is on disk"):
          before = events()
          t.assertEqual(switch("v3"), 0)
          t.assertEqual(events()[len(before) :], ["app-start-3.0.0"])

      with subtest("downgrade is refused"):
          before = events()
          t.assertNotEqual(switch("v2"), 0)
          machine.succeed(f"systemctl is-failed {PRE}")
          machine.fail("systemctl is-active fakeapp.service")
          t.assertIn("refusing to move from version 3.0.0 back to 2.0.0", unit_log(PRE))
          t.assertEqual(events()[len(before) :], [])
          t.assertEqual(stamp(), {"version": "3.0.0", "phase": "complete"})
          t.assertEqual(switch("v3"), 0)

      with subtest("skipping a release series is refused"):
          before = events()
          t.assertNotEqual(switch("skipping"), 0)
          machine.succeed(f"systemctl is-failed {PRE}")
          t.assertIn("at least one major release series is skipped", unit_log(PRE))
          t.assertEqual(events()[len(before) :], [])
          t.assertEqual(stamp(), {"version": "3.0.0", "phase": "complete"})

      with subtest("control: the same jump is allowed without a skip limit"):
          before = events()
          t.assertEqual(switch("bigJump"), 0)
          t.assertEqual(
              events()[len(before) :],
              ["on-upgrade", "app-start-9.0.0", "on-upgrade-post"],
          )
          t.assertEqual(stamp(), {"version": "9.0.0", "phase": "complete"})

      with subtest("an existing installation without a stamp is backfilled, not reinitialised"):
          before = events()
          machine.succeed("rm ${stamp}")
          restart_all()
          t.assertEqual(events()[len(before) :], ["app-start-9.0.0"])
          t.assertEqual(stamp(), {"version": "9.0.0", "phase": "complete"})
          t.assertIn("without a recorded version", unit_log(PRE))

      with subtest("control: without data it is treated as a fresh installation"):
          before = events()
          machine.succeed("rm ${stamp} ${dataFile}")
          restart_all()
          t.assertEqual(events()[len(before) :], ["fresh", "app-start-9.0.0"])
          t.assertEqual(stamp(), {"version": "9.0.0", "phase": "complete"})
    '';
}
