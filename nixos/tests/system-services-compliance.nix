{
  pkgs,
  evalSystem,
  runTest,
  callTest,
}:

let
  sharedDir = "/tmp/modular-service-compliance";

  inherit (pkgs) lib coreutils;

  evalSystemServices =
    services:
    evalSystem (
      { ... }:
      {
        system.services = services;
        system.stateVersion = "25.05";
        fileSystems."/" = {
          device = "/test/dummy";
          fsType = "auto";
        };
        boot.loader.grub.enable = false;
      }
    );
in
let
  suite = pkgs.testers.modularServiceCompliance {
    inherit sharedDir;
    namePrefix = "system-services-compliance";
    evalConfig =
      { services }:
      let
        machine = evalSystemServices services;
      in
      {
        config = machine.config.system.services;
        checkDrv = machine.config.system.build.toplevel;
        # Integration-specific: the resolved host systemd units, so systemd-only
        # attributes like serviceConfig.Type/ExecReload can be asserted. Optional;
        # non-systemd integrations need not provide it.
        systemdUnits = machine.config.systemd.services;
      };
    mkTest =
      {
        name,
        services,
        testExe,
      }:
      runTest {
        _class = "nixosTest";
        inherit name;
        nodes.machine.system.services = services;
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.succeed("${testExe}")
        '';
        meta.maintainers = with pkgs.lib.maintainers; [ roberth ];
      };
  };

  # systemd-specific eval assertions. serviceConfig.Type/ExecReload only exist on
  # the resolved host units, so a fresh eval is used per case.
  systemdEvalTests =
    let
      defaultUnits =
        (evalSystemServices {
          service.process.argv = [ "${coreutils}/bin/true" ];
        }).config.systemd.services;

      notifyUnits =
        (evalSystemServices {
          service = {
            process.argv = [ "${coreutils}/bin/true" ];
            notificationProtocol.systemd = true;
          };
        }).config.systemd.services;

      reloadUnits =
        (evalSystemServices {
          service = {
            process.argv = [ "${coreutils}/bin/true" ];
            process.reloadSignal = "HUP";
          };
        }).config.systemd.services;
    in
    {
      testDefaultType = {
        expr = defaultUnits.service.serviceConfig.Type;
        expected = "simple";
      };

      testNotifyType = {
        expr = notifyUnits.service.serviceConfig.Type;
        expected = "notify";
      };

      testReloadExecReload = {
        expr = reloadUnits.service.serviceConfig.ExecReload;
        expected = "${coreutils}/bin/kill -HUP $MAINPID";
      };
    };

  systemdEval = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    __structuredAttrs = true;
    name = "system-services-compliance-systemd-eval-report";
    passthru = {
      tests = systemdEvalTests;
      failures = lib.runTests finalAttrs.passthru.tests;
    };
    testResults = lib.mapAttrs (_: test: test.expr == test.expected) finalAttrs.passthru.tests;
    buildCommand = ''
      touch $out
      for testName in "''${!testResults[@]}"; do
        if [[ -n "''${testResults[$testName]}" ]]; then
          echo "PASS  $testName"
        else
          echo "FAIL  $testName"
        fi
      done
    ''
    + lib.optionalString (lib.any (v: !v) (lib.attrValues finalAttrs.testResults)) ''
      {
        echo ""
        echo "systemd-specific eval-level compliance failures:"
        for testName in "''${!testResults[@]}"; do
          if [[ -z "''${testResults[$testName]}" ]]; then
            echo "- $testName"
          fi
        done
      } >&2
      exit 1
    '';
  });
in

# Please the callTest pattern.
#
# runTest results already go through findTests/callTest.
# For plain derivations like `eval`, we apply callTest directly.
pkgs.lib.mapAttrs (
  _: v:
  if v ? test then
    v
  else
    callTest {
      test = v;
      driver = v;
    }
) (suite // { systemd-eval = systemdEval; })
