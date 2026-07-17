# Run:
#   nix-instantiate --eval lib/services/test-kubernetes.nix
#
# Exercises `toKubernetesManifests` against a hermetic inline modular service
# that sets the portable `process.*` metadata the generator reads (ports,
# environment, capabilities, directories.state, configData). No package
# dependency, so the mapping from metadata to manifest is tested in isolation.
let
  pkgs = import ../.. { };
  lib = pkgs.lib;

  portable-lib = import ./lib.nix { inherit lib; };

  toKubernetesManifests = import ./to-kubernetes.nix { inherit lib; };

  configured = portable-lib.configure {
    serviceManagerPkgs = pkgs;
  };

  # A minimal modular service declaring exactly the metadata the generator maps.
  exampleEval = lib.evalModules {
    modules = [
      {
        options.services = lib.mkOption {
          type = lib.types.attrsOf configured.serviceSubmodule;
        };
      }
      {
        services.example = {
          process.argv = [ "/bin/example" ];
          process.ports.metrics = { port = 9598; };
          process.environment.EXAMPLE_LOG = "info";
          process.capabilities = [ "net_bind_service" ];
          process.directories.state = "example";
          configData."example.toml".text = "key = \"value\"\n";
        };
      }
    ];
  };

  exampleConfig = exampleEval.config.services.example;

  m = toKubernetesManifests {
    name = "example";
    image = "example:latest";
    config = exampleConfig;
    namespace = "monitoring";
  };

  workload = m.workload;
  service = m.service;
  configMap = m.configMap;
  container = builtins.head workload.spec.template.spec.containers;

in
# -- workload is a StatefulSet (because process.directories.state is set) --
assert workload.kind == "StatefulSet";
assert workload.apiVersion == "apps/v1";
assert workload.metadata.name == "example";
assert workload.metadata.namespace == "monitoring";
assert workload.spec.serviceName == "example";
assert workload.spec.replicas == 1;

# -- selector and labels match --
assert workload.spec.selector.matchLabels == workload.spec.template.metadata.labels;

# -- container basics --
assert container.name == "example";
assert container.image == "example:latest";

# -- process.ports -> containerPort --
assert builtins.length container.ports == 1;
assert (builtins.head container.ports).containerPort == 9598;
assert (builtins.head container.ports).name == "metrics";
assert (builtins.head container.ports).protocol == "TCP";

# -- process.environment -> env --
assert builtins.length container.env == 1;
assert (builtins.head container.env).name == "EXAMPLE_LOG";
assert (builtins.head container.env).value == "info";

# -- process.capabilities -> securityContext --
assert container.securityContext.capabilities.add == [ "NET_BIND_SERVICE" ];

# -- process.directories.state -> PVC + volumeMount --
assert builtins.length workload.spec.volumeClaimTemplates == 1;
assert (builtins.head workload.spec.volumeClaimTemplates).metadata.name == "state-example";
assert builtins.any (
  vm: vm.name == "state-example" && vm.mountPath == "/var/lib/example"
) container.volumeMounts;

# -- configData -> configMap volume + mount --
assert builtins.any (
  v: v.name == "config" && v.configMap.name == "example-config"
) workload.spec.template.spec.volumes;
assert builtins.any (vm: vm.name == "config" && vm.readOnly == true) container.volumeMounts;

# -- Service --
assert service.kind == "Service";
assert service.apiVersion == "v1";
assert service.metadata.name == "example";
assert service.metadata.namespace == "monitoring";
assert builtins.length service.spec.ports == 1;
assert (builtins.head service.spec.ports).port == 9598;
assert (builtins.head service.spec.ports).name == "metrics";
assert (builtins.head service.spec.ports).protocol == "TCP";
assert service.spec.selector == workload.spec.template.metadata.labels;

# -- ConfigMap --
assert configMap.kind == "ConfigMap";
assert configMap.metadata.name == "example";
assert configMap ? data;
assert configMap.data ? "example.toml";

"ok"
