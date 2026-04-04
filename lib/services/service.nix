# Non-module arguments
# These are separate from the module arguments to avoid implicit dependencies.
# This makes service modules self-contains, allowing mixing of Nixpkgs versions.
#
# Portable service base module - imported into every modular service's module system.
#
# Defines the core service interface (`process.argv`, `process.ports`,
# `process.user`, `process.directories`, `process.capabilities`,
# `process.environment`, sub-`services`, `configData`)
# and imports the contracts module. This is system-agnostic: it works regardless of
# whether the containing system is NixOS, home-manager, or similar systems.
#
# Contract state propagates from parent services to sub-services automatically,
# with `_upstreamContracts.*.results` scoped to each service's own entries.
#
# Service-manager-specific options (systemd units, launchd plists, etc.) are added
# via `extraRootModules` in `lib/services/lib.nix`'s `configure` function, not here.
{ pkgs }:

# The module
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  pathOrStr = types.coercedTo types.path (x: "${x}") types.str;
in
{
  # https://nixos.org/manual/nixos/unstable/#modular-services
  _class = "service";
  imports = [
    ../../modules/generic/meta-maintainers.nix
    ../../nixos/modules/misc/assertions.nix
    (lib.modules.importApply ./config-data.nix { inherit pkgs; })
    ../contracts/module.nix
  ];
  options = {
    services = mkOption {
      type = types.attrsOf (
        types.submoduleWith {
          modules = [
            (lib.modules.importApply ./service.nix { inherit pkgs; })
            # Propagate contract state to sub-services. Scope `_upstreamContracts`
            # so sub-service results are accessible via just `${name}`.
            (
              { name, ... }:
              {
                config = {
                  inherit (config) contractTypes;
                  _upstreamContracts = lib.mapAttrs (
                    _: contract:
                    contract
                    // {
                      results = contract.results.${name} or { };
                    }
                  ) config._upstreamContracts;
                };
              }
            )
          ];
        }
      );
      description = ''
        A collection of [modular services](https://nixos.org/manual/nixos/unstable/#modular-services) that are configured in one go.

        You could consider the sub-service relationship to be an ownership relation.
        It **does not** automatically create any other relationship between services (e.g. systemd slices), unless perhaps such a behavior is explicitly defined and enabled in another option.
      '';
      default = { };
      visible = "shallow";
    };
    process = {
      argv = lib.mkOption {
        type = types.listOf pathOrStr;
        example = lib.literalExpression ''[ (lib.getExe config.package) "--nobackground" ]'';
        description = ''
          Command filename and arguments for starting this service.
          This is a raw command-line that should not contain any shell escaping.
          If expansion of environmental variables is required then use
          a shell script or `importas` from `pkgs.execline`.
        '';
      };
      user = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "User name for the service process.";
            };
            group = mkOption {
              type = types.str;
              description = "Primary group name.";
            };
            home = mkOption {
              type = types.nullOr types.str;
              description = "Home directory path, or null for no dedicated home.";
            };
            createHome = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to create the home directory if it does not exist.";
            };
          };
        });
        description = ''
          User identity for the service process.

          When set, the execution context ensures this user and group exist.
          On NixOS, this creates `users.users` and `users.groups` entries and
          sets `User=` / `Group=` in the systemd unit.

          For complex requirements (fixed UID/GID, extra groups, login shell),
          use execution-context-specific options instead.
        '';
      };
      directories = {
        state = mkOption {
          type = types.nullOr types.str;
          description = ''
            Persistent state directory for the service.

            On NixOS/systemd, maps to `StateDirectory` when the path follows
            the `/var/lib/<name>` convention, otherwise generates tmpfiles rules.
          '';
          example = "myservice";
        };
        cache = mkOption {
          type = types.nullOr types.str;
          description = ''
            Cache directory (may be cleared between restarts).

            On NixOS/systemd, maps to `CacheDirectory`.
          '';
        };
        runtime = mkOption {
          type = types.nullOr types.str;
          description = ''
            Runtime directory (cleared on reboot).

            On NixOS/systemd, maps to `RuntimeDirectory`.
          '';
        };
        logs = mkOption {
          type = types.nullOr types.str;
          description = ''
            Log directory for the service.

            On NixOS/systemd, maps to `LogsDirectory`.
          '';
        };
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Environment variables set for the service process.

          On NixOS/systemd, these are passed via the systemd unit's
          `Environment` directive.
        '';
        example = {
          RUST_LOG = "info";
          PORT = "8080";
        };
      };
      capabilities = mkOption {
        type = types.listOf (types.enum [
          "net_bind_service"
          "net_raw"
          "sys_time"
          "dac_override"
          "dac_read_search"
          "chown"
          "fowner"
          "kill"
          "setuid"
          "setgid"
        ]);
        default = [ ];
        description = ''
          Linux capabilities required by the service process.
          Uses lowercase names without the `CAP_` prefix.

          Execution contexts interpret this appropriately:
          - systemd: sets `AmbientCapabilities` and `CapabilityBoundingSet`
          - containers: adds to the container capability set
          - k8s: sets `securityContext.capabilities.add`
        '';
      };
      ports = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            port = mkOption {
              type = types.nullOr types.port;
              description = ''
                Single port number. Mutually exclusive with `range`.
              '';
            };
            range = mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  from = mkOption {
                    type = types.port;
                    description = "Start of port range (inclusive).";
                  };
                  to = mkOption {
                    type = types.port;
                    description = "End of port range (inclusive).";
                  };
                };
              });
              description = ''
                Port range (inclusive). Mutually exclusive with `port`.
              '';
            };
            protocol = mkOption {
              type = types.enum [ "tcp" "udp" ];
              default = "tcp";
              description = "Transport protocol.";
            };
          };
        });
        default = { };
        description = ''
          Named network ports this service listens on.

          This is declarative metadata about what ports the service process uses.
          Execution contexts interpret this appropriately: NixOS can open firewall
          ports, containers can set EXPOSE directives, orchestrators can configure
          service port specs.

          Port names should be descriptive (e.g. "http", "grpc", "metrics").
        '';
      };
    };
  };
  config.assertions = lib.concatLists (lib.mapAttrsToList (name: portCfg: [
    {
      assertion = (portCfg.port != null) != (portCfg.range != null);
      message = "process.ports.${name}: set either `port` or `range`, not both or neither.";
    }
  ]) config.process.ports);
}
