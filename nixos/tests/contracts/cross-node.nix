# Demonstrates the canonical shared-eval pattern for sharing computed
# values between two NixOS nodes via the module system.
#
# Contracts are fundamentally a Nix evaluation-time mechanism: there is
# no shared `config` between separately-evaluated nodes, so wiring is
# done by evaluating the consumer+fulfiller composition once in a
# `lib.evalModules` call and injecting the resulting value into each
# node's configuration at eval time.
#
# The contract option comes from `lib.contract.module`; on NixOS nodes
# it is registered via the module list, so the test bodies only carry
# consumer/fulfiller wiring.
{ pkgs, lib, ... }:
let
  # Consumer side: declares the requested input value.
  consumerModule = {
    contracts.arithmetic.want.value = 5;
  };

  # Fulfiller side: computes the result from the want.
  fulfillerModule = { config, ... }: {
    contracts.arithmetic.result.value = config.contracts.arithmetic.want.value + 1;
  };

  # Shared evaluation: composes consumer and fulfiller against the
  # generic contracts module so both nodes derive their value from
  # one source of truth.
  sharedContracts =
    (lib.evalModules {
      modules = [
        lib.contract.module
        consumerModule
        fulfillerModule
      ];
    }).config;

  resultValue = sharedContracts.contracts.arithmetic.result.value;
in
{
  name = "contracts-cross-node";

  nodes = {
    # Provider node: serves the eval-time result over HTTP so the
    # consumer can verify it at runtime. In a real use case this would
    # be a proper service (e.g. a secrets manager).
    provider = { pkgs, ... }: {
      imports = [ fulfillerModule ];
      systemd.services.arithmetic-server = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          mkdir -p /run/arithmetic
          echo -n ${lib.escapeShellArg (toString resultValue)} > /run/arithmetic/result
          exec ${pkgs.python3}/bin/python3 -m http.server 8080 --directory /run/arithmetic
        '';
      };
      networking.firewall.allowedTCPPorts = [ 8080 ];
    };

    # Consumer node: bakes the shared-eval result into its configuration
    # at evaluation time, so it has the expected value baked in without
    # talking to the provider.
    consumer = {
      imports = [ consumerModule ];
      environment.etc."arithmetic-expected".text = toString resultValue;
    };
  };

  testScript = ''
    provider.wait_for_unit("arithmetic-server.service")
    consumer.wait_for_unit("multi-user.target")

    expected = consumer.succeed("cat /etc/arithmetic-expected").strip()
    assert expected == "${toString resultValue}", f"contract result mismatch: got {expected!r}"

    served = consumer.succeed("curl -sf http://provider:8080/result").strip()
    assert served == expected, f"provider served {served!r}, consumer expected {expected!r}"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
