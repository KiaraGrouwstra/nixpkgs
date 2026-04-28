# systemd-openbaod: broker secrets from OpenBao to systemd services.
#
# This module is a thin bridge to the NixOS modules shipped with the-distro's
# systemd-openbao, fetched at the same revision that `pkgs.systemd-openbaod` is
# built from so the daemon and its modules stay in lockstep. Rather than
# re-implementing the broker here, it imports:
#
#   - systemd-openbaod.nix: the `/run/systemd-openbaod/sock` socket + daemon,
#     plus (via openbao-secrets.nix) per-service `vault.*` options that deliver
#     secrets through `LoadCredential` / `EnvironmentFile` and run
#     `try-reload-or-restart` on rotation.
#   - openbao-agent.nix: `services.openbao.agents.<name>`, each running
#     `bao agent` to render the templates the services above declare. An agent
#     with no templates is disabled, so the unit stays absent until a service
#     actually targets it.
#
# On top of the imported broker, this module exposes two contract providers
# backed by it:
#
#   - `envSecrets`: a consumer requests a set of environment variables bound to
#     a unit; the provider renders them into one `vault.environmentTemplate` and
#     the broker delivers the resulting `EnvironmentFile` (with reload on
#     rotation).
#   - `fileSecrets`: a consumer requests a single secret file; the provider
#     composes the requested lines into one file rendered through the broker
#     (as a unit `EnvironmentFile`, so the broker handles ordering and reload)
#     and returns its path.
#
# Both providers are backed by the same daemon agent, so a host runs a single
# `openbao agent` for all per-service secrets. The broker itself stays
# contracts-agnostic; the contract glue lives here in nixpkgs.
#
# The source is fetched with `builtins.fetchTarball` (a fixed-output fetch, not
# IFD) mirroring the npins pattern, so eval stays pure. The revision and hash
# track `pkgs/by-name/sy/systemd-openbaod/package.nix`; bump both together.
#
# The daemon's systemd service is socket-activated (it is not wanted by any
# target), so on a host that declares no agents and no `vault.*` secrets only
# the unix socket is created and the daemon never starts. Opt-in gating of the
# socket itself is left to a follow-up PR against the-distro.
{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  src = builtins.fetchTarball {
    url = "https://git.lix.systems/kiaragrouwstra/systemd-openbao/archive/bde10de699a3f25834134f7374e3a9f557c19fac.tar.gz";
    sha256 = "36zy/0Nqpgd7xvwrg/2N+dtQTOT8F8UZbMohueF/jD4=";
  };

  cfg = config.services.systemd-openbaod;

  inherit (lib) mkOption mkIf types;
  inherit (types)
    attrsOf
    bool
    str
    submodule
    ;

  # A `{ path; field; base64Decode; }` line, shared by the envSecrets provider's
  # request variables and the fileSecrets provider's composed lines.
  lineType = submodule {
    options = {
      path = mkOption {
        type = str;
        description = "Provider-specific read path of the secret holding this value.";
      };
      field = mkOption {
        type = str;
        default = "content";
        description = "Field within the secret at `path` holding the value.";
      };
      base64Decode = mkOption {
        type = bool;
        default = true;
        description = "Whether to base64-decode the field value before writing it.";
      };
    };
  };

  # Go-template line rendering one environment variable from a secret at a KV
  # read path. The broker feeds these to `bao agent`, which renders them into
  # the unit's EnvironmentFile.
  renderLine =
    varName: line:
    let
      value =
        if line.base64Decode then
          "{{ .Data.data.${line.field} | base64Decode }}"
        else
          "{{ .Data.data.${line.field} }}";
    in
    ''
      {{ with secret "${line.path}" -}}
      ${varName}=${value}
      {{- end }}'';

  # An environment-file template: one rendered line per requested variable.
  envTemplate = lines: lib.concatStringsSep "\n" (lib.mapAttrsToList renderLine lines) + "\n";

  # Broker path the rendered environment file ends up at for a given unit.
  envFilePath = unit: "/run/systemd-openbaod/secrets/${unit}.service.EnvironmentFile";

  # Flatten a provider's nested instances (`<consumer>.<instance> = { request; ... }`)
  # to a flat list of leaf instance submodules for iteration.
  flatten =
    instances:
    let
      go = v: if v ? request then [ v ] else lib.concatMap go (lib.attrValues v);
    in
    go instances;
in
{
  imports = [
    "${src}/nix/modules/systemd-openbaod.nix" # also pulls in openbao-secrets.nix
    "${src}/nix/modules/openbao-agent.nix"
  ];

  options.services.systemd-openbaod = {
    enable = lib.mkEnableOption "the systemd-openbaod contract providers (envSecrets, fileSecrets) backed by the broker";

    envSecrets = mkOption {
      default = config.contracts.envSecrets.requests;
      defaultText = lib.literalExpression "config.contracts.envSecrets.requests";
      description = ''
        `envSecrets` provider instances. Each request delivers a set of
        environment variables to its `unit` via a broker-rendered
        `EnvironmentFile`, reloading the unit on rotation.
      '';
      type = config.contracts.envSecrets.mkProviderType {
        fulfill' =
          { request, ... }:
          {
            inherit (request) unit;
            environmentFile = envFilePath request.unit;
          };
      };
    };

    fileSecrets = mkOption {
      default = config.contracts.fileSecrets.requests;
      defaultText = lib.literalExpression "config.contracts.fileSecrets.requests";
      description = ''
        `fileSecrets` provider instances. Each request composes the configured
        `lines` into a single environment-style secret file rendered through the
        broker, returning its path. The file is delivered to `unit` as an
        `EnvironmentFile` so the broker handles ordering and reload; consumers
        that read the file directly point at `result.path`.
      '';
      type = config.contracts.fileSecrets.mkProviderType {
        providerOptions = {
          unit = mkOption {
            type = str;
            description = ''
              systemd unit (without `.service`) the rendered file is attached to;
              the broker wires ordering and reload onto it, and `result.path`
              resolves to the broker's render path for that unit.
            '';
          };
          lines = mkOption {
            type = attrsOf lineType;
            default = { };
            description = ''
              `KEY = { path; field; base64Decode; }` entries composed into the
              rendered secret file, each read from the secret at `path`.
            '';
          };
        };
        fulfill' =
          { request, instance, ... }:
          {
            path = envFilePath instance.unit;
          };
      };
    };
  };

  config = lib.mkMerge [
    {
      # One source of truth for the daemon binary: the nixpkgs package built from
      # the same revision the imported modules come from.
      services.systemd-openbaod.package = pkgs.systemd-openbaod;
    }

    (mkIf cfg.enable {
      # Register the providers so consumers can select them.
      contracts.envSecrets.providers.systemd-openbaod.module =
        options.services.systemd-openbaod.envSecrets;
      contracts.fileSecrets.providers.systemd-openbaod.module =
        options.services.systemd-openbaod.fileSecrets;

      # Translate each provider instance into the broker's per-service `vault.*`.
      # Both contracts render a unit `environmentTemplate`; the broker emits the
      # `<unit>-envfile.service` ordering shim and reloads on rotation.
      systemd.services = lib.mkMerge (
        (map (inst: {
          ${inst.request.unit}.vault.environmentTemplate = envTemplate inst.request.variables;
        }) (flatten cfg.envSecrets))
        ++ (map (inst: {
          ${inst.unit}.vault.environmentTemplate = envTemplate inst.lines;
        }) (lib.filter (inst: inst.lines != { }) (flatten cfg.fileSecrets)))
      );
    })
  ];
}
