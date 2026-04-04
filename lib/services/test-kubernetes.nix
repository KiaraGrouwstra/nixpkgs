# Run:
#   nix-instantiate --eval lib/services/test-kubernetes.nix
let
  pkgs = import ../.. {};
  lib = pkgs.lib;

  portable-lib = import ./lib.nix { inherit lib; };

  toKubernetesManifests = import ./to-kubernetes.nix { inherit lib; };

  configured = portable-lib.configure {
    serviceManagerPkgs = pkgs;
  };

  # Evaluate vector as a modular service
  vectorEval = lib.evalModules {
    modules = [
      {
        options.services = lib.mkOption {
          type = lib.types.attrsOf configured.serviceSubmodule;
        };
      }
      {
        services.vector = {
          imports = [ pkgs.vector.services.default ];
          vector = {
            journaldAccess = true;
            settings = {
              sources.journald.type = "journald";
              sources.vector_metrics.type = "internal_metrics";
              sinks.prometheus_exporter = {
                type = "prometheus_exporter";
                inputs = [ "vector_metrics" ];
                address = "[::]:9598";
              };
            };
          };
          process.ports.metrics = { port = 9598; };
          process.environment.VECTOR_LOG = "info";
        };
      }
    ];
  };

  vectorConfig = vectorEval.config.services.vector;

  m = toKubernetesManifests {
    name = "vector";
    image = "vector:${pkgs.vector.version}";
    config = vectorConfig;
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
  assert workload.metadata.name == "vector";
  assert workload.metadata.namespace == "monitoring";
  assert workload.spec.serviceName == "vector";
  assert workload.spec.replicas == 1;

  # -- selector and labels match --
  assert workload.spec.selector.matchLabels == workload.spec.template.metadata.labels;

  # -- container basics --
  assert container.name == "vector";
  assert container.image == "vector:${pkgs.vector.version}";

  # -- process.ports -> containerPort --
  assert builtins.length container.ports == 1;
  assert (builtins.head container.ports).containerPort == 9598;
  assert (builtins.head container.ports).name == "metrics";
  assert (builtins.head container.ports).protocol == "TCP";

  # -- process.environment -> env --
  assert builtins.length container.env == 1;
  assert (builtins.head container.env).name == "VECTOR_LOG";
  assert (builtins.head container.env).value == "info";

  # -- process.capabilities -> securityContext --
  assert container.securityContext.capabilities.add == [ "NET_BIND_SERVICE" ];

  # -- process.directories.state -> PVC + volumeMount --
  assert builtins.length workload.spec.volumeClaimTemplates == 1;
  assert (builtins.head workload.spec.volumeClaimTemplates).metadata.name == "state-vector";
  assert builtins.any (vm: vm.name == "state-vector" && vm.mountPath == "/var/lib/vector") container.volumeMounts;

  # -- configData -> configMap volume + mount --
  assert builtins.any (v: v.name == "config" && v.configMap.name == "vector-config") workload.spec.template.spec.volumes;
  assert builtins.any (vm: vm.name == "config" && vm.readOnly == true) container.volumeMounts;

  # -- Service --
  assert service.kind == "Service";
  assert service.apiVersion == "v1";
  assert service.metadata.name == "vector";
  assert service.metadata.namespace == "monitoring";
  assert builtins.length service.spec.ports == 1;
  assert (builtins.head service.spec.ports).port == 9598;
  assert (builtins.head service.spec.ports).name == "metrics";
  assert (builtins.head service.spec.ports).protocol == "TCP";
  assert service.spec.selector == workload.spec.template.metadata.labels;

  # -- ConfigMap --
  assert configMap.kind == "ConfigMap";
  assert configMap.metadata.name == "vector";
  assert configMap ? data;
  assert configMap.data ? "vector.toml";

  "ok"
