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
  # Multiple consumers register at distinct paths under one contract to
  # demonstrate `nestedAttrsOf` namespacing.
  consumerModule = {
    contracts.arithmetic.want = {
      alice.value = 5;
      bob.deep.path.value = 10;
    };
  };

  # Fulfiller side: walks the want tree and produces a parallel result
  # tree, computing each leaf as `value + 1`. Note: walking and writing
  # the same `nestedAttrsOf` option would recurse on its merged spine
  # (the fulfiller's own contribution would feed back into the walk),
  # so we walk `want` and write to `result` -- distinct options.
  fulfillerModule = { config, ... }: let
    walk = w:
      if w ? value then { value = w.value + 1; }
      else builtins.mapAttrs (_: walk) w;
  in {
    contracts.arithmetic.result = walk config.contracts.arithmetic.want;
  };

  # Shared evaluation: composes consumer and fulfiller against the
  # generic contracts module so both nodes derive their values from
  # one source of truth.
  sharedContracts =
    (lib.evalModules {
      modules = [
        lib.contract.module
        ./arithmetic-contract.nix
        consumerModule
        fulfillerModule
      ];
    }).config;

  aliceResult = sharedContracts.contracts.arithmetic.result.alice.value;
  bobResult = sharedContracts.contracts.arithmetic.result.bob.deep.path.value;
in
{
  name = "contracts-cross-node";

  nodes = {
    # Provider node: serves the eval-time results over HTTP so the
    # consumer can verify them at runtime.
    provider = { pkgs, ... }: {
      imports = [ ./arithmetic-contract.nix fulfillerModule ];
      systemd.services.arithmetic-server = {
        wantedBy = [ "multi-user.target" ];
        script = ''
          mkdir -p /run/arithmetic
          echo -n ${lib.escapeShellArg (toString aliceResult)} > /run/arithmetic/alice
          echo -n ${lib.escapeShellArg (toString bobResult)} > /run/arithmetic/bob
          exec ${pkgs.python3}/bin/python3 -m http.server 8080 --directory /run/arithmetic
        '';
      };
      networking.firewall.allowedTCPPorts = [ 8080 ];
    };

    # Consumer node: bakes the shared-eval results into its configuration
    # at evaluation time, so it has the expected values baked in without
    # talking to the provider.
    consumer = {
      imports = [ ./arithmetic-contract.nix consumerModule ];
      environment.etc."arithmetic-expected-alice".text = toString aliceResult;
      environment.etc."arithmetic-expected-bob".text = toString bobResult;
    };
  };

  testScript = ''
    provider.wait_for_unit("arithmetic-server.service")
    consumer.wait_for_unit("multi-user.target")

    for name, expected in [("alice", "${toString aliceResult}"), ("bob", "${toString bobResult}")]:
        baked = consumer.succeed(f"cat /etc/arithmetic-expected-{name}").strip()
        assert baked == expected, f"{name}: baked {baked!r} != expected {expected!r}"
        served = consumer.succeed(f"curl -sf http://provider:8080/{name}").strip()
        assert served == expected, f"{name}: provider served {served!r}, expected {expected!r}"
  '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
