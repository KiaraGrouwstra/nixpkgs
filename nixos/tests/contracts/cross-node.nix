# Demonstrates the canonical shared-eval pattern for sharing computed
# values between two NixOS nodes via the module system.
#
# Contracts are fundamentally a Nix evaluation-time mechanism: there is
# no shared `config` between separately-evaluated nodes, so wiring is
# done by evaluating the consumer+fulfiller composition once in a
# `lib.evalModules` call and injecting the resulting value into each
# node's configuration at eval time.
#
# This iteration drops the inline contract option in favor of the
# generic `lib.contract.module` registry: the `arithmetic` contract is
# declared once in `./arithmetic-contract.nix` and consumed via
# `config.contracts.arithmetic.*` in both NixOS modules and the bare
# `lib.evalModules` composition.
{ pkgs, lib, ... }:
let
  # Multiple consumers register at distinct paths under one contract to
  # demonstrate namespacing.
  consumerModule = {
    contracts.arithmetic.want = {
      alice.request.value = 5;
      bob.deep.path.request.value = 10;
    };
  };

  # Fulfiller side: reads consumer inputs through the read-only
  # `requests` projection (symmetric with how the consumer reads
  # `results`) and writes each leaf's `result` back into `want`,
  # computing `value + 1`. The fulfiller targets the consumer-declared
  # leaves explicitly: writing into the same option whose spine we'd
  # walk to discover paths generically would otherwise recurse.
  fulfillerModule = { config, ... }: let
    requests = config.contracts.arithmetic.requests;
  in {
    contracts.arithmetic.want = {
      alice.result.value = requests.alice.value + 1;
      bob.deep.path.result.value = requests.bob.deep.path.value + 1;
    };
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

  aliceResult = sharedContracts.contracts.arithmetic.results.alice.value;
  bobResult = sharedContracts.contracts.arithmetic.results.bob.deep.path.value;
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
