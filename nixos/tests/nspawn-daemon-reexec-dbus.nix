# Regression test for an nspawn-only systemd re-exec failure that breaks D-Bus.
#
# Trigger
# -------
# `switch-to-configuration-ng` issues a D-Bus `Manager.Reexecute` whenever the
# systemd package changed between generations
# (pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs, `systemd.reexecute()`
# in the `restart_systemd` block). `systemctl daemon-reexec` issues the
# identical `Manager.Reexecute`, so it is a faithful minimal trigger that needs
# no second generation. This test just loops `daemon-reexec`.
#
# Two distinct breakages, two distinct probes
# -------------------------------------------
# Inside a systemd-nspawn test container (`--keep-unit --register=no
# --private-users=no`, host `/proc` + `/sys` bind-mounted), PID 1 re-sends
# `READY=1` on the `NOTIFY_SOCKET` (an AF_UNIX SOCK_DGRAM) on every re-exec.
#
#   (A) DRIVER-TRANSPORT break. The test driver stopped draining the notify
#       socket once boot finished, so its receive buffer filled and PID 1's
#       `sendmsg()` blocked in `unix_wait_for_peer`. The re-exec'd systemd never
#       finished re-initialising, so every subsequent in-container call through
#       the driver's `nsenter` backdoor hung or returned `Transport endpoint is
#       not connected`. This is a *test-tooling* artifact: it only exists
#       because the driver owns the notify socket. Fixed by keeping a daemon
#       thread draining the socket for the container's whole lifetime
#       (nixos/lib/test-driver/.../machine/__init__.py).
#
#   (B) IN-CONTAINER OWN-BUS break. Independently of the driver, after the
#       re-exec the container's *own* D-Bus (the system bus broker reachable at
#       /run/dbus/system_bus_socket) can stop answering, so a `systemctl start`
#       run entirely inside the container -- e.g. over SSH, the way a real
#       `nixos-rebuild`/`switch-to-configuration` deploy reaches the host --
#       hangs until its `timeout` kills it (status 124). This is NOT a
#       test-tooling artifact: nothing here goes through the driver socket.
#
# This test probes BOTH transports after every re-exec so the two breakages can
# be told apart:
#   - `backdoor_broken()` uses `machine.execute` (the driver `nsenter` path) ->
#     observes (A).
#   - `own_bus_broken()` SSHes from a sibling QEMU node into the container and
#     runs the probe there, touching only the container's own bus -> observes
#     (B), and is immune to the driver-socket fix.
#
# QEMU machines route no systemd notifications through a host-side driver socket
# and never exhibit either break (verified: the identical loop survives
# indefinitely there).
{ lib, ... }:
{
  name = "nspawn-daemon-reexec-dbus";

  # nspawn tests need uid-range / /dev/net/tun, not available on Hydra by
  # default (mirrors nixos/tests/nixos-test-driver/containers.nix).
  meta.hydraPlatforms = [ ];

  # `containers.<name>` => systemd-nspawn machine (vs `nodes.<name>` => QEMU).
  # The container runs sshd so a sibling node can reach its own bus over SSH,
  # exercising the same in-container D-Bus path a real deploy uses.
  containers.machine =
    { ... }:
    {
      services.openssh = {
        enable = true;
        # Persistent service, not socket-activated: the probe needs a live
        # sshd that does not depend on a working bus to spawn per-connection.
        startWhenNeeded = false;
        settings.PermitRootLogin = "yes";
        settings.PermitEmptyPasswords = "yes";
      };
      users.users.root.password = "";
      security.pam.services.sshd.allowNullPassword = true;
      networking.firewall.allowedTCPPorts = [ 22 ];
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

  testScript = # python
    ''
      import re

      BUS_BROKEN = re.compile(
          r"Transport endpoint is not connected|Failed to connect to bus"
      )

      # Before any fix a bare re-exec loop wedged within a couple dozen
      # iterations. 40 keeps the test bounded while reliably surfacing a
      # regression.
      REEXECS = 40


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
          the OUTPUT, not the SSH/timeout exit code: `client.execute` reports
          the transport's own status (which can be nonzero/-1 even when the
          remote command succeeded), so a working bus is recognised by the
          expected state token coming back, and a broken bus by the transport
          error string or by no usable output (hang killed by `timeout`)."""
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

      # Pre-reexec sanity: both transports work.
      b, bs, bo = backdoor_broken()
      assert not b, f"backdoor already broken before any reexec: status={bs} out={bo!r}"
      o, os_, oo = own_bus_broken()
      assert not o, f"own bus already broken before any reexec: status={os_} out={oo!r}"
      machine.log(f"pre-reexec sanity OK: backdoor={bo.strip()!r} ssh={oo.strip()!r}")

      backdoor_broke_at = None
      own_bus_broke_at = None
      for i in range(1, REEXECS + 1):
          # The same D-Bus Manager.Reexecute that switch-to-configuration issues
          # on a systemd change.
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
          if b and backdoor_broke_at is None:
              backdoor_broke_at = i
          if o and own_bus_broke_at is None:
              own_bus_broke_at = i
          if backdoor_broke_at is not None and own_bus_broke_at is not None:
              break

      # Report both independently so a run pins down which break occurred.
      machine.log(
          f"SUMMARY: backdoor_broke_at={backdoor_broke_at} "
          f"own_bus_broke_at={own_bus_broke_at} (of {REEXECS})"
      )

      assert backdoor_broke_at is None, (
          f"(A) driver-transport: nspawn backdoor bus broke after daemon-reexec "
          f"#{backdoor_broke_at} of {REEXECS}. The re-exec'd PID 1 never finished "
          "re-initialising because the test driver stopped draining the notify "
          "socket, so PID 1's READY=1 resend blocked. Never observed on QEMU."
      )
      assert own_bus_broke_at is None, (
          f"(B) in-container own bus: the container's system bus stopped "
          f"answering an SSH-driven `systemctl` after daemon-reexec "
          f"#{own_bus_broke_at} of {REEXECS}, the way a real "
          "switch-to-configuration deploy reaches it. This is independent of the "
          "driver notify-socket fix. Never observed on QEMU."
      )
    '';
}
