# Tests contracts spanning separate NixOS nodes, with both consumer and provider
# implemented as modular services.
#
# Mirrors `cross-node.nix` but demonstrates that the cross-node pattern works
# equally well when each side is a modular service rather than a plain NixOS module.
{ lib, ... }:
let
  portable-lib = import ../../../lib/services/lib.nix { inherit lib; };

  # `configured` references `rootContracts` which is resolved from the shared eval,
  # and the shared eval uses `configured.serviceSubmodule`. This is safe under Nix
  # lazy evaluation: consumer `want` is static, so `requests` can be computed before
  # any `result` is forced. No data cycle exists.
  configured = portable-lib.configure {
    serviceManagerPkgs = throw "shared eval does not need pkgs";
    contracts = rootContracts;
    upstreamContractDefinitions = rootContractDefs;
  };

  consumerServiceModule =
    { lib, config, ... }:
    {
      _class = "service";
      options.consumer.operation = lib.mkOption {
        default.result = config.contracts.arithmetic.results.operation;
        type = config.contractDefinitions.arithmetic.mkContract { };
      };
      config = {
        consumer.operation.request.value = 5;
        contracts.arithmetic.want = { inherit (config.consumer) operation; };
        process.argv = [ "/run/current-system/sw/bin/true" ];
      };
    };

  providerServiceModule = ./arithmetic-increment-provider.nix;

  sharedContracts =
    (lib.evalModules {
      modules = [
        # Bundles `lib.contract.module` + meta stub + arithmetic contract definition.
        ../../../lib/tests/modules/contracts-arithmetic-contract.nix
        (
          { lib, ... }:
          {
            options.services = lib.mkOption {
              type = lib.types.attrsOf configured.serviceSubmodule;
              default = { };
            };
          }
        )
        # Manual lift: surfaces each service's want/providers at the root contracts
        # namespace. This is the same job the bridge does, written inline to show
        # that the bridge is just a small piece of Nix, not a hard requirement.
        (
          { config, lib, ... }:
          {
            contracts.arithmetic = {
              want = lib.mapAttrs (_: svc: svc.contracts.arithmetic.want) config.services;
              providers = lib.foldl' (acc: svc: acc // svc.contracts.arithmetic.providers) { } (
                lib.attrValues config.services
              );
            };
            contracts.arithmetic.defaultProviderName = "increment";
          }
        )
        {
          services.consumer.imports = [ consumerServiceModule ];
          services.increment.imports = [ providerServiceModule ];
        }
      ];
    }).config;

  rootContracts = sharedContracts.contracts;
  rootContractDefs = sharedContracts.contractDefinitions;

  resultValue = sharedContracts.contracts.arithmetic.results.consumer.operation.value;
in
{
  name = "contracts-cross-node-modular-services";

  nodes = {
    provider =
      { pkgs, ... }:
      {
        imports = [ ./arithmetic-contract.nix ];
        system.services.increment.imports = [ providerServiceModule ];
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

    consumer =
      { ... }:
      {
        imports = [ ./arithmetic-contract.nix ];
        system.services.instance.imports = [ consumerServiceModule ];
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
