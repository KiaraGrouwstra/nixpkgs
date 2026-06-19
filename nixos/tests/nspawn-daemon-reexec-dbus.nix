# Regression test for an nspawn-only systemd re-exec failure that breaks D-Bus.
#
# Trigger
# -------
# `switch-to-configuration-ng` issues a D-Bus `Manager.Reexecute` whenever the
# systemd package changed between generations: `restart_systemd` is true when
# the running PID 1 binary path differs from the new toplevel's
# (pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs, `current_pid1_path
# != new_pid1_path` at ~:2031, then `systemd.reexecute()` at ~:2326). That
# reexecute runs for the `switch` AND `test` actions (it sits past the `boot`
# early-exit), so `switch-to-configuration test` against a toplevel built with a
# different systemd is a faithful minimal trigger that needs no bootloader
# install (which nspawn cannot do).
#
# This test exercises TWO triggers of increasing fidelity:
#   1. bare `systemctl daemon-reexec` -- the isolated `Manager.Reexecute`.
#   2. `switch-to-configuration test` against a sibling toplevel whose systemd
#      store path differs -- a real activation: unit stop/start churn PLUS the
#      reexec, the way an actual `nixos-rebuild`/`switch-to-configuration` deploy
#      reaches the host.
#
# Two distinct breakages, two distinct probes
# -------------------------------------------
# Inside a systemd-nspawn test container (`--keep-unit --register=no
# --private-users=no`, host `/proc` + `/sys` bind-mounted, `--notify-ready=yes`),
# PID 1 re-sends `READY=1` on the `NOTIFY_SOCKET` (an AF_UNIX SOCK_DGRAM) on
# every re-exec.
#
#   (A) DRIVER-TRANSPORT break. The test driver stopped draining the notify
#       socket once boot finished, so its receive buffer filled and PID 1's
#       `sendmsg()` blocked in `unix_wait_for_peer`. The re-exec'd systemd never
#       finished re-initialising, so every subsequent in-container call -- even
#       one arriving over SSH rather than the driver backdoor -- hung, because
#       the container's whole init was frozen. This is a *test-tooling* artifact:
#       it only exists because the driver owns the notify socket. Fixed by
#       keeping a daemon thread draining the socket for the container's whole
#       lifetime (nixos/lib/test-driver/.../machine/__init__.py).
#
#   (B) IN-CONTAINER OWN-BUS break. Independently of the driver -- i.e. with the
#       notify socket kept drained so PID 1 never wedges -- a *real* activation
#       can still leave the container's own D-Bus (the system bus broker at
#       /run/dbus/system_bus_socket) unable to answer, so a `systemctl` run
#       entirely inside the container over SSH hangs until its `timeout` kills it
#       (status 124). nothing in that path goes through the driver socket, so
#       this is not a test-tooling artifact.
#
# This test probes BOTH transports after every trigger so the two breakages can
# be told apart:
#   - `backdoor_broken()` uses `machine.execute` (the driver `nsenter` path) ->
#     observes (A).
#   - `own_bus_broken()` SSHes from a sibling QEMU node into the container and
#     runs the probe there, touching only the container's own bus -> observes
#     (B), and is immune to the driver-socket fix.
#
# QEMU machines route no systemd notifications through a host-side driver socket
# and never exhibit (A); a QEMU contrast is the cleanest way to attribute any
# surviving break to (B).
{ lib, pkgs, ... }:
let
  # A systemd whose store path differs from the booted one, so
  # switch-to-configuration sees `current_pid1_path != new_pid1_path` and issues
  # the real `Manager.Reexecute`. The change is a no-op marker file: behaviour
  # is identical, only the hash moves.
  systemdReexecMarker = pkgs.systemd.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      echo "nspawn-daemon-reexec-dbus reexec marker" \
        > "$out/lib/systemd/.nspawn-reexec-marker"
    '';
  });

  # A trivial D-Bus policy package. Adding it to `services.dbus.packages`
  # changes `configDir` (the broker's config dir is built from the union of all
  # such packages), so switch-to-configuration sees `dbus-broker.service`'s
  # `restartTriggers = [ configDir ]` fire and issues a *reload* (the unit is
  # `reloadIfChanged = true`) of the running system bus broker DURING the same
  # activation that reexecs systemd. A real deploy hits this whenever a service
  # with a bus policy is added/removed; the bare-reexec and marker-only triggers
  # never touched the broker, which is the gap this closes.
  dbusPolicyPackage = pkgs.runCommand "nspawn-reexec-dbus-policy" { } ''
    mkdir -p "$out/share/dbus-1/system.d"
    cat > "$out/share/dbus-1/system.d/nspawn-reexec-dbus.conf" <<'EOF'
    <!DOCTYPE busconfig PUBLIC
      "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
      "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
    <busconfig>
      <policy context="default">
        <allow own="org.nspawn.ReexecDbusReproMarker"/>
      </policy>
    </busconfig>
    EOF
  '';

  containerCommon = {
    services.openssh = {
      enable = true;
      # Persistent service, not socket-activated: the probe needs a live sshd
      # that does not depend on a working bus to spawn per-connection.
      startWhenNeeded = false;
      settings.PermitRootLogin = "yes";
      settings.PermitEmptyPasswords = "yes";
    };
    users.users.root.password = "";
    security.pam.services.sshd.allowNullPassword = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
in
{
  name = "nspawn-daemon-reexec-dbus";

  # nspawn tests need uid-range / /dev/net/tun, not available on Hydra by
  # default (mirrors nixos/tests/nixos-test-driver/containers.nix).
  meta.hydraPlatforms = [ ];

  # `containers.<name>` => systemd-nspawn machine (vs `nodes.<name>` => QEMU).
  # The container runs sshd so a sibling node can reach its own bus over SSH,
  # exercising the same in-container D-Bus path a real deploy uses.
  containers.machine = { ... }: containerCommon;

  # A second container config, never started. Built only for its toplevel: it is
  # identical to `machine` except (a) its systemd store path differs, so running
  # `${otherSystem}/bin/switch-to-configuration test` inside `machine` issues the
  # package-change reexec, and (b) it adds a D-Bus policy package, so the same
  # activation also reloads the running system bus broker (configDir changed) --
  # the broker-touching activation a real deploy performs and the bare reexec
  # never did.
  containers.other =
    { ... }:
    lib.recursiveUpdate containerCommon {
      systemd.package = systemdReexecMarker;
      services.dbus.packages = [ dbusPolicyPackage ];
    };

  # A plain QEMU node used only as the SSH client into the container, so the
  # own-bus probe never touches the driver's nsenter backdoor.
  nodes.client =
    { ... }:
    {
      programs.ssh.extraConfig = ''
        Host machine
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      '';
    };

  testScript =
    { containers, ... }:
    let
      otherSystem = containers.other.system.build.toplevel;
    in
    # python
    ''
      import re

      BUS_BROKEN = re.compile(
          r"Transport endpoint is not connected|Failed to connect to bus"
      )

      # Both triggers below break (when they break at all) within a couple dozen
      # iterations. These bounds keep the test short while reliably surfacing a
      # regression.
      REEXECS = 40
      SWITCHES = 20

      OTHER_SWITCHER = "${otherSystem}/bin/switch-to-configuration"


      def backdoor_broken():
          """(A) One bounded read-only bus call through the driver nsenter
          backdoor. A wedged bus prints the transport error or hangs until the
          `timeout` kills it (status 124). All count as broken."""
          status, out = machine.execute(
              "timeout 10 systemctl show -p ActiveState --value "
              "multi-user.target 2>&1",
              check_return=False,
              timeout=20,
          )
          return status != 0 or bool(BUS_BROKEN.search(out)), status, out


      def own_bus_broken():
          """(B) The same bounded probe, but run INSIDE the container over SSH
          from the client node, so it touches only the container's own system
          bus -- exactly the path a real `switch-to-configuration` deploy uses.
          Immune to the driver notify-socket fix.

          A healthy bus returns the unit's ActiveState ('active'). We judge on
          the OUTPUT, not the SSH/timeout exit code: `client.execute` reports the
          transport's own status (which can be nonzero/-1 even when the remote
          command succeeded), so a working bus is recognised by the expected
          state token coming back, and a broken bus by the transport error
          string or by no usable output (hang killed by `timeout`)."""
          _status, out = client.execute(
              "timeout 20 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "
              "-o UserKnownHostsFile=/dev/null root@machine "
              "'timeout 10 systemctl show -p ActiveState --value "
              "multi-user.target 2>&1'",
              check_return=False,
              timeout=40,
          )
          broken = bool(BUS_BROKEN.search(out)) or ("active" not in out)
          return broken, _status, out


      machine.start()
      client.start()
      machine.wait_for_unit("multi-user.target", timeout=120)
      machine.wait_for_open_port(22, timeout=120)
      client.wait_for_unit("multi-user.target", timeout=120)

      # Pre-trigger sanity: both transports work.
      b, bs, bo = backdoor_broken()
      assert not b, f"backdoor already broken before any trigger: status={bs} out={bo!r}"
      o, os_, oo = own_bus_broken()
      assert not o, f"own bus already broken before any trigger: status={os_} out={oo!r}"
      machine.log(f"pre-trigger sanity OK: backdoor={bo.strip()!r} ssh={oo.strip()!r}")

      # ---- Phase 1: bare `daemon-reexec` (the isolated Manager.Reexecute) ----
      reexec_backdoor_broke_at = None
      reexec_own_bus_broke_at = None
      for i in range(1, REEXECS + 1):
          machine.execute(
              "timeout 30 systemctl daemon-reexec",
              check_return=False,
              timeout=45,
          )
          b, bs, bo = backdoor_broken()
          o, os_, oo = own_bus_broken()
          machine.log(
              f"[reexec {i}] backdoor: status={bs} out={bo.strip()!r} | "
              f"own-bus: status={os_} out={oo.strip()!r}"
          )
          if b and reexec_backdoor_broke_at is None:
              reexec_backdoor_broke_at = i
          if o and reexec_own_bus_broke_at is None:
              reexec_own_bus_broke_at = i
          if reexec_backdoor_broke_at is not None and reexec_own_bus_broke_at is not None:
              break

      # ---- Phase 2: real `switch-to-configuration test` (churn + reexec) ----
      # Each switch alternates between the `other` toplevel and the booted one, so
      # both deltas flip on every iteration: the systemd store path differs
      # (`current_pid1_path != new_pid1_path` -> package-change reexec) AND the
      # D-Bus configDir differs (`other` carries an extra bus policy ->
      # `dbus-broker.service` restartTriggers fire -> a system-bus reload). That
      # reload-the-broker-while-reexecing-PID-1 combination is the real-deploy
      # path the bare reexec and marker-only switch never exercised.
      switch_backdoor_broke_at = None
      switch_own_bus_broke_at = None
      if reexec_backdoor_broke_at is None:
          for i in range(1, SWITCHES + 1):
              # Alternate: odd iterations run `other`'s switcher (the live system,
              # which has neither the bus policy nor the marker systemd, is the
              # baseline -> activating `other` ADDS both -> reexec + broker reload),
              # even iterations run the booted system's own switcher (relative to
              # the still-booted baseline this is a no-op -> nothing fires, a clean
              # control). `test` never persists `/run/current-system`, so the
              # baseline stays the booted system and `other test` re-applies its
              # full delta every odd iteration.
              if i % 2 == 1:
                  switcher = OTHER_SWITCHER
              else:
                  switcher = "/run/current-system/bin/switch-to-configuration"
              # Run the switcher entirely inside the container, the way a deploy
              # would; bounded so a wedged activation fails fast.
              machine.execute(
                  f"timeout 90 {switcher} test 2>&1",
                  check_return=False,
                  timeout=120,
              )
              b, bs, bo = backdoor_broken()
              o, os_, oo = own_bus_broken()
              machine.log(
                  f"[switch {i}] backdoor: status={bs} out={bo.strip()!r} | "
                  f"own-bus: status={os_} out={oo.strip()!r}"
              )
              if b and switch_backdoor_broke_at is None:
                  switch_backdoor_broke_at = i
              if o and switch_own_bus_broke_at is None:
                  switch_own_bus_broke_at = i
              if switch_backdoor_broke_at is not None and switch_own_bus_broke_at is not None:
                  break
      else:
          machine.log(
              "skipping phase 2: backdoor already broke in phase 1, so PID 1 is "
              "wedged and a real switch cannot run cleanly"
          )

      machine.log(
          f"SUMMARY: reexec(backdoor={reexec_backdoor_broke_at} "
          f"own_bus={reexec_own_bus_broke_at} of {REEXECS}) "
          f"switch(backdoor={switch_backdoor_broke_at} "
          f"own_bus={switch_own_bus_broke_at} of {SWITCHES})"
      )

      assert reexec_backdoor_broke_at is None, (
          f"(A) driver-transport: nspawn backdoor bus broke after daemon-reexec "
          f"#{reexec_backdoor_broke_at} of {REEXECS}. The re-exec'd PID 1 never "
          "finished re-initialising because the test driver stopped draining the "
          "notify socket, so PID 1's READY=1 resend blocked. Never observed on QEMU."
      )
      assert switch_backdoor_broke_at is None, (
          f"(A) driver-transport: nspawn backdoor bus broke after a real "
          f"switch-to-configuration #{switch_backdoor_broke_at} of {SWITCHES}, "
          "same notify-socket wedge as the bare-reexec case."
      )
      assert reexec_own_bus_broke_at is None and switch_own_bus_broke_at is None, (
          f"(B) in-container own bus: the container's system bus stopped "
          f"answering an SSH-driven `systemctl` after "
          f"reexec #{reexec_own_bus_broke_at} / switch "
          f"#{switch_own_bus_broke_at}, the way a real switch-to-configuration "
          "deploy reaches it. This is independent of the driver notify-socket "
          "fix. Never observed on QEMU."
      )
    '';
}
