# Tests contracts spanning separate NixOS nodes, with both consumer and provider
# implemented as modular services.
#
# Variant of `cross-node-modular-services.nix` that selects the default provider
# via `defaultProvider` (direct assignment) instead of `defaultProviderName`.
# Exercises the direct-assignment code path in `lib/services/lib.nix::evalServices`.
{ lib, ... }:
let
  portable-lib = import ../../../lib/services/lib.nix { inherit lib; };

  arithmeticContract = ./arithmetic-contract.nix;

  consumerServiceModule =
    { lib, config, ... }:
    {
      _class = "service";
      imports = [ arithmeticContract ];
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

  providerNode = {
    imports = [ arithmeticContract ];
    system.services.increment.imports = [
      ./arithmetic-increment-provider.nix
      (
        { config, ... }:
        {
          contracts.arithmetic.defaultProvider = config.contracts.arithmetic.providers.increment;
        }
      )
    ];
  };

  evaluated = portable-lib.evalServices {
    services = {
      consumer = consumerServiceModule;
      increment = providerNode.system.services.increment;
    };
  };

  resultValue = evaluated.contracts.arithmetic.results.consumer.operation.value;
in
{
  name = "contracts-cross-node-modular-services-direct";

  nodes = {
    provider =
      { pkgs, ... }:
      {
        imports = [
          providerNode
          {
            systemd.services.arithmetic-server = {
              wantedBy = [ "multi-user.target" ];
              script = ''
                mkdir -p /run/arithmetic
                echo -n ${lib.escapeShellArg (toString resultValue)} > /run/arithmetic/result
                exec ${pkgs.python3}/bin/python3 -m http.server 8080 --directory /run/arithmetic
              '';
            };
            networking.firewall.allowedTCPPorts = [ 8080 ];
          }
        ];
      };

    consumer =
      { ... }:
      {
        imports = [ arithmeticContract ];
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
