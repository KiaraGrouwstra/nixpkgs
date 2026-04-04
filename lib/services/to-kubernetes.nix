# Generate Kubernetes manifests from an evaluated modular service configuration.
#
# Usage:
#   toKubernetesManifests {
#     name = "vector";
#     image = "vector:latest";
#     config = evaluatedServiceConfig;
#   }
#
# Returns an attrset of k8s resource manifests (Deployment, Service, ConfigMap).
{ lib }:
let
  inherit (lib)
    concatLists
    concatMapAttrs
    filter
    mapAttrs
    mapAttrsToList
    optional
    optionalAttrs
    ;

  flattenServices = f: config:
    f config
    ++ concatLists (mapAttrsToList (_: sub: flattenServices f sub) config.services);

  collectPorts = config:
    flattenServices (svc: mapAttrsToList (name: p: p // { inherit name; }) svc.process.ports) config;

  collectEnv = config:
    flattenServices (svc: mapAttrsToList (k: v: { inherit k v; }) svc.process.environment) config;

  collectCapabilities = config:
    flattenServices (svc: svc.process.capabilities) config;

  collectConfigData = config:
    flattenServices (svc:
      mapAttrsToList (name: cfg: { inherit name; inherit (cfg) source enable; })
        (svc.configData or { })
    ) config;

  collectDirectories = config:
    flattenServices (svc:
      let d = svc.process.directories; in
      optional (d.state != null) { type = "state"; value = d.state; mountPath = "/var/lib/${d.state}"; }
      ++ optional (d.cache != null) { type = "cache"; value = d.cache; mountPath = "/var/cache/${d.cache}"; }
      ++ optional (d.runtime != null) { type = "runtime"; value = d.runtime; mountPath = "/run/${d.runtime}"; }
      ++ optional (d.logs != null) { type = "logs"; value = d.logs; mountPath = "/var/log/${d.logs}"; }
    ) config;

in
{
  name,
  image,
  config,
  namespace ? "default",
  replicas ? 1,
}:
let
  ports = collectPorts config;
  singlePorts = filter (p: p.port != null) ports;
  env = collectEnv config;
  caps = collectCapabilities config;
  configData = filter (c: c.enable) (collectConfigData config);
  dirs = collectDirectories config;
  stateDirs = filter (d: d.type == "state") dirs;
  ephemeralDirs = filter (d: d.type != "state") dirs;
  user = config.process.user;

  labels = {
    "app.kubernetes.io/name" = name;
    "app.kubernetes.io/managed-by" = "nix";
  };

  configMapName = "${name}-config";

  containerPorts = map (p: {
    name = p.name;
    containerPort = p.port;
    protocol = lib.toUpper p.protocol;
  }) singlePorts;

  containerEnv = map (e: {
    name = e.k;
    value = e.v;
  }) env;

  securityContext =
    optionalAttrs (caps != []) {
      capabilities.add = map (c: lib.toUpper c) caps;
    }
    // optionalAttrs (user != null) {
      runAsUser = 1000;
      runAsGroup = 1000;
    };

  configVolumeMounts = optional (configData != []) {
    name = "config";
    mountPath = "/etc/config";
    readOnly = true;
  };

  stateVolumeMounts = map (d: {
    name = "state-${d.value}";
    mountPath = d.mountPath;
  }) stateDirs;

  ephemeralVolumeMounts = map (d: {
    name = "${d.type}-${d.value}";
    mountPath = d.mountPath;
  }) ephemeralDirs;

  configVolumes = optional (configData != []) {
    name = "config";
    configMap.name = configMapName;
  };

  ephemeralVolumes = map (d: {
    name = "${d.type}-${d.value}";
    emptyDir = {};
  }) ephemeralDirs;

  useStatefulSet = stateDirs != [];

in
{
  configMap = lib.optionalAttrs (configData != []) {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      inherit name namespace labels;
    };
    data = lib.listToAttrs (map (c: {
      name = c.name;
      value = builtins.readFile c.source;
    }) configData);
  };

  service = lib.optionalAttrs (singlePorts != []) {
    apiVersion = "v1";
    kind = "Service";
    metadata = {
      inherit name namespace labels;
    };
    spec = {
      selector = labels;
      ports = map (p: {
        inherit (p) name;
        port = p.port;
        targetPort = p.name;
        protocol = lib.toUpper p.protocol;
      }) singlePorts;
    };
  };

  workload =
    let
      podSpec = {
        containers = [
          ({
            inherit name image;
          }
          // optionalAttrs (containerPorts != []) {
            ports = containerPorts;
          }
          // optionalAttrs (containerEnv != []) {
            env = containerEnv;
          }
          // optionalAttrs (securityContext != {}) {
            inherit securityContext;
          }
          // optionalAttrs (configVolumeMounts ++ stateVolumeMounts ++ ephemeralVolumeMounts != []) {
            volumeMounts = configVolumeMounts ++ stateVolumeMounts ++ ephemeralVolumeMounts;
          })
        ];
      }
      // optionalAttrs (configVolumes ++ ephemeralVolumes != []) {
        volumes = configVolumes ++ ephemeralVolumes;
      };
    in
    if useStatefulSet then {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        inherit name namespace labels;
      };
      spec = {
        inherit replicas;
        selector.matchLabels = labels;
        serviceName = name;
        template = {
          metadata = { inherit labels; };
          spec = podSpec;
        };
        volumeClaimTemplates = map (d: {
          metadata.name = "state-${d.value}";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
          };
        }) stateDirs;
      };
    } else {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        inherit name namespace labels;
      };
      spec = {
        inherit replicas;
        selector.matchLabels = labels;
        template = {
          metadata = { inherit labels; };
          spec = podSpec;
        };
      };
    };
}
