# Non-module arguments
# These are separate from the module arguments to avoid implicit dependencies.
# This makes service modules self-contains, allowing mixing of Nixpkgs versions.
#
# Portable service base module - imported into every modular service's module system.
#
# Defines the core service interface (`process.argv`, `process.ports`,
# `process.reloadSignal`, `process.reloadCommand`, `notificationProtocol`,
# sub-`services`, `configData`)
# and imports the contracts module. This is system-agnostic: it works regardless of
# whether the containing system is NixOS, home-manager, or similar systems.
#
# Contract state propagates from parent services to sub-services automatically,
# with `contracts.*.results` scoped to each service's own entries via direct injection.
#
# Service-manager-specific options (systemd units, launchd plists, etc.) are added
# via `extraRootModules` in `lib/services/lib.nix`'s `configure` function, not here.
{ pkgs }:

# The module
{
  lib,
  config,
  options,
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
    lib.contract.module
  ];
  options = {
    services = mkOption {
      type = types.attrsOf (
        types.submoduleWith {
          modules = [
            (lib.modules.importApply ./service.nix { inherit pkgs; })
            # Propagate contract state to sub-services, scoping results
            # so sub-service results are accessible via just the option name.
            (
              { name, ... }:
              {
                config = {
                  inherit (config) contractDefinitions;
                  contracts = lib.mapAttrs (contractType: _: {
                    results = lib.mkForce (config.contracts.${contractType}.results.${name} or { });
                    defaultProvider = lib.mkForce config.contracts.${contractType}.defaultProvider;
                  }) config.contractDefinitions;
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

      reloadSignal = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "HUP";
        description = ''
          Configures the reload signal to send to the service manager.
        '';
      };

      reloadCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = lib.literalExpression ''"''${pkgs.coreutils}/bin/kill -HUP $MAINPID"'';
        description = ''
          Command used for reloading in the underlying service manager to reload.
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

    notificationProtocol = mkOption {
      type = types.submodule {
        options = {
          systemd = mkOption {
            default = false;
            example = true;
            description = "Whether the service supports systemd-notify.";
            type = lib.types.bool;
          };
          s6 = mkOption {
            default = false;
            example = true;
            description = "Whether the service supports s6-notify.";
            type = lib.types.bool;
          };
        };
      };
      description = ''
        Notification protocol that this service supports with the underlying service manager.
      '';
    };
  };

  config = {
    assertions = [
      {
        # `reloadSignal` derives `reloadCommand` at `mkDefault` priority below, so a
        # conflict only exists when the user *also* set `reloadCommand` explicitly.
        # An explicit (non-`mkDefault`) definition has `defaultOverridePriority`.
        assertion =
          !(
            config.process.reloadSignal != null
            && options.process.reloadCommand.highestPrio <= lib.modules.defaultOverridePriority
          );
        message = "reloadSignal conflicts with reloadCommand. Please either use reloadSignal or reloadCommand.";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: portCfg: [
        {
          assertion = (portCfg.port != null) != (portCfg.range != null);
          message = "process.ports.${name}: set either `port` or `range`, not both or neither.";
        }
      ]) config.process.ports
    );

    process.reloadCommand = lib.mkIf (config.process.reloadSignal != null) (
      lib.mkDefault "${pkgs.coreutils}/bin/kill -${config.process.reloadSignal} $MAINPID"
    );
  };
}
