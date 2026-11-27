# Run:
#   nix-build -A nixosTests.modularService

{
  evalSystem,
  runCommand,
  hello,
  ...
}:

let
  machine = evalSystem (
    { lib, ... }:
    let
      hello' = lib.getExe hello;
    in
    {

      # Test input

      system.services.foo = {
        process = {
          argv = [
            hello'
            "--greeting"
            "hoi"
          ];
        };
      };
      system.services.bar = {
        process = {
          argv = [
            hello'
            "--greeting"
            "hoi"
          ];
        };
        systemd.service = {
          serviceConfig.X-Bar = "lol crossbar whatever";
        };
        services.db = {
          process = {
            argv = [
              hello'
              "--greeting"
              "Hi, I'm a database, would you believe it"
            ];
          };
          systemd.service = {
            serviceConfig.RestartSec = "42";
          };
        };
      };

      # Test that systemd.mainExecStart overrides process.argv
      # and allows systemd's specifier and variable substitution
      system.services.argv-with-subst = {
        process = {
          argv = [
            hello'
            "--greeting"
            "This should be ignored"
          ];
        };
        systemd.mainExecStart = ''/bin/sh -c "echo %n and ''${HOME}"'';
      };

      # Test that process.argv escapes % and $ by default
      system.services.argv-escaped = {
        process = {
          argv = [
            "/bin/sh"
            "-c"
            "echo %n and \${HOME}"
          ];
        };
      };

      # Test extending process.argv with systemd specifiers
      system.services.argv-extended =
        { config, ... }:
        {
          process = {
            argv = [
              hello'
              "--greeting"
              "Fun $1 fact, remainder is often expressed as m%n"
            ];
          };
          systemd.mainExecStart =
            config.systemd.lib.escapeSystemdExecArgs config.process.argv + " --systemd-unit %n";
        };

      # Test the settings derived from `security.capabilities`
      system.services.caps-none = {
        process.argv = [ hello' ];
        security.capabilities = [ ];
      };
      system.services.caps-some = {
        process.argv = [ hello' ];
        security.capabilities = [ "CAP_NET_BIND_SERVICE" ];
        # A sub-service gets its own settings
        services.all = {
          process.argv = [ hello' ];
          security.capabilities = [
            "CAP_SYS_ADMIN"
            "CAP_SYS_BOOT"
            "CAP_SYS_RAWIO"
            "CAP_SYS_MODULE"
            "CAP_SYSLOG"
          ];
        };
      };
      # Definitions of the service override the derived settings
      system.services.caps-override = {
        process.argv = [ hello' ];
        security.capabilities = [ ];
        systemd.service.serviceConfig = {
          CapabilityBoundingSet = [ "CAP_CHOWN" ];
          PrivateUsers = false;
          SystemCallFilter = "@system-service";
        };
      };

      # irrelevant stuff
      system.stateVersion = "25.05";
      fileSystems."/" = {
        device = "/test/dummy";
        fsType = "auto";
      };
      boot.loader.grub.enable = false;
    }
  );

  inherit (machine.config.system.build) toplevel;

  # `PrivateUsers` needs user namespaces
  noUserNamespaces = machine.extendModules {
    modules = [
      {
        security.allowUserNamespaces = false;
        nix.settings.sandbox = false;
      }
    ];
  };
in
assert !(noUserNamespaces.config.systemd.services.caps-none.serviceConfig ? PrivateUsers);
assert noUserNamespaces.config.systemd.services.caps-none.serviceConfig.ProtectKernelLogs;
runCommand "test-modular-service-systemd-units"
  {
    passthru = {
      inherit
        machine
        noUserNamespaces
        toplevel
        ;
    };
  }
  ''
    echo ${toplevel}/etc/systemd/system/foo.service:
    cat -n ${toplevel}/etc/systemd/system/foo.service
    # `! grep` does not stop the script on a match, because `set -e` ignores it
    absent() {
      if grep -q "^$1=" "$2"; then echo "unexpected $1 in $2"; exit 1; fi
    }
    (
      set -x
      grep -F 'ExecStart="${hello}/bin/hello" "--greeting" "hoi"' ${toplevel}/etc/systemd/system/foo.service >/dev/null

      grep -F 'ExecStart="${hello}/bin/hello" "--greeting" "hoi"' ${toplevel}/etc/systemd/system/bar.service >/dev/null
      grep -F 'X-Bar=lol crossbar whatever' ${toplevel}/etc/systemd/system/bar.service >/dev/null

      grep    'ExecStart="${hello}/bin/hello" "--greeting" ".*database.*"' ${toplevel}/etc/systemd/system/bar-db.service >/dev/null
      grep -F 'RestartSec=42' ${toplevel}/etc/systemd/system/bar-db.service >/dev/null

      # Test that systemd.mainExecStart overrides process.argv
      # Note: %n and $HOME are NOT escaped, allowing systemd to substitute them
      grep -F 'ExecStart=/bin/sh -c "echo %n and ''${HOME}"' ${toplevel}/etc/systemd/system/argv-with-subst.service >/dev/null

      # Test that process.argv escapes % as %% and $ as $$
      # This prevents systemd from performing specifier/variable substitution
      grep -F 'ExecStart="/bin/sh" "-c" "echo %%n and $${HOME}"' ${toplevel}/etc/systemd/system/argv-escaped.service >/dev/null

      # Test extending process.argv with systemd specifiers
      # The base command should be escaped ($1 -> $$1, m%n -> m%%n), but the appended --systemd-unit %n should not be
      grep -F 'ExecStart="${hello}/bin/hello" "--greeting" "Fun $$1 fact, remainder is often expressed as m%%n" --systemd-unit %n' ${toplevel}/etc/systemd/system/argv-extended.service >/dev/null

      # Unknown capabilities: no derived settings
      for key in CapabilityBoundingSet AmbientCapabilities ProtectKernelModules ProtectKernelLogs SystemCallFilter PrivateUsers; do
        absent "$key" ${toplevel}/etc/systemd/system/foo.service
      done

      # No capabilities
      unit=${toplevel}/etc/systemd/system/caps-none.service
      grep -qx 'CapabilityBoundingSet=' $unit
      grep -qx 'AmbientCapabilities=' $unit
      grep -qx 'ProtectKernelModules=true' $unit
      grep -qx 'ProtectKernelLogs=true' $unit
      grep -qx 'PrivateUsers=true' $unit
      absent ProtectClock $unit
      [[ "$(grep '^SystemCallFilter=' $unit)" == "$(printf '%s\n' \
        'SystemCallFilter=~@raw-io:EPERM' \
        'SystemCallFilter=~@reboot:EPERM' \
        'SystemCallFilter=~@swap:EPERM')" ]]

      # Some capabilities
      unit=${toplevel}/etc/systemd/system/caps-some.service
      grep -qx 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' $unit
      grep -qx 'AmbientCapabilities=CAP_NET_BIND_SERVICE' $unit
      grep -qx 'ProtectKernelModules=true' $unit
      grep -qx 'ProtectKernelLogs=true' $unit
      [[ $(grep -c '^SystemCallFilter=' $unit) == 3 ]]
      absent PrivateUsers $unit

      # The capabilities that the derived settings remove
      unit=${toplevel}/etc/systemd/system/caps-some-all.service
      grep -qx 'CapabilityBoundingSet=CAP_SYS_ADMIN' $unit
      for key in ProtectKernelModules ProtectKernelLogs SystemCallFilter PrivateUsers; do
        absent "$key" $unit
      done

      # Overrides; the allow list comes before the denied groups
      unit=${toplevel}/etc/systemd/system/caps-override.service
      grep -qx 'CapabilityBoundingSet=CAP_CHOWN' $unit
      grep -qx 'AmbientCapabilities=' $unit
      grep -qx 'PrivateUsers=false' $unit
      [[ "$(grep '^SystemCallFilter=' $unit | head -1)" == 'SystemCallFilter=@system-service' ]]
      [[ $(grep -c '^SystemCallFilter=' $unit) == 4 ]]

      [[ ! -e ${toplevel}/etc/systemd/system/foo.socket ]]
      [[ ! -e ${toplevel}/etc/systemd/system/bar.socket ]]
      [[ ! -e ${toplevel}/etc/systemd/system/bar-db.socket ]]
    )
    echo 🐬👍
    touch $out
  ''
