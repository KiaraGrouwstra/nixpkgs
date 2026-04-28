# OpenBao varsBackend provider.
#
# After generate-vars produces files locally, the upload-vars-openbao service
# uploads them to an OpenBao KV v2 mount (keeping the local copies, which
# LoadCredential consumers read at activation). On subsequent boots the shared
# `openbao agent` (services.openbao.agents.<agent>) fetches the secrets from
# OpenBao into a tmpfs directory with the requested permissions, rendering them
# through the same agent that the systemd-openbaod broker uses for per-service
# secrets -- so a host runs a single agent for everything.
#
# The vars templates are contributed to the agent via the broker's
# `extraTemplates` merge point (an additive list the broker concatenates into
# `settings.template`), so vars and the broker compose without colliding on the
# freeform `settings.template` attribute.
#
# Requires:
# - A running OpenBao server
# - An `openbao agent` instance configured with authentication pointed at it
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.services.vars-openbao;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "varsBackend";
  inherit (config.contracts.${contract}) mkProviderType;

  isSelected = config.contracts.${contract}.defaultProviderName == "openbao";

  varsBackendType = (options.services.vars-openbao.type.getSubOptions [ ]).${contract}.type;

  # KV path for a file within the configured mount.
  kvPath =
    instanceName: fileName: secret:
    "${cfg.prefix}/${if secret then "secret" else "public"}/${instanceName}/${fileName}";

  # Local path where the agent writes fetched files (= provider result path).
  localPath =
    instanceName: fileName: secret:
    "${cfg.tmpDir}/${if secret then "secret" else "public"}/${instanceName}/${fileName}";

  # Flatten instances for iteration in runtime services. Key on the leaf
  # name to match what `fulfill'` sees: the contract framework passes the
  # deepest submodule key, not the joined path. `services.vars`'s
  # `generate-vars` writes through `backendFiles` using that same leaf
  # name, so keying here on `lib.last path` keeps all three sides
  # (generate, upload, fetch) agreeing on the same paths.
  flatInstances = lib.concatMapNestedAttrs' varsBackendType (path: instance: {
    ${lib.last path} = instance;
  }) cfg.${contract};

  # Shell snippet that sets VAULT_ADDR and VAULT_TOKEN.
  authEnv = ''
    export VAULT_ADDR="''${VAULT_ADDR:-${cfg.address}}"
    export VAULT_TOKEN
    VAULT_TOKEN=$(< ${lib.escapeShellArg cfg.tokenFile})
  '';

  # Uploads locally-generated files to OpenBao and removes local copies.
  upload-vars = pkgs.writeShellApplication {
    name = "upload-vars-openbao";
    runtimeInputs = [
      pkgs.openbao
      pkgs.coreutils
    ];
    text = ''
      ${authEnv}

      ${lib.concatMapStringsSep "\n" (
        { name, instance }:
        let
          req = instance.request;
        in
        ''
          echo "=== Uploading: ${name} ==="
          ${lib.concatMapStringsSep "\n" (
            fileName:
            let
              file = req.files.${fileName};
              kv = kvPath name fileName file.secret;
              path = localPath name fileName file.secret;
            in
            ''
              if [ -f ${lib.escapeShellArg path} ]; then
                bao kv put \
                  -mount=${lib.escapeShellArg cfg.mount} \
                  ${lib.escapeShellArg kv} \
                  content="$(base64 < ${lib.escapeShellArg path})"
                echo "  Uploaded ${fileName}"
                # Keep the local copy: LoadCredential consumers read it at
                # unit activation, which can race the agent's first render
                # (the agent becomes active before templates are on disk).
              else
                echo "  Skipping ${fileName} (already in OpenBao or not yet generated)"
              fi
            ''
          ) (lib.attrNames req.files)}
        ''
      ) (lib.mapAttrsToList (name: instance: { inherit name instance; }) flatInstances)}

      echo "Upload complete."
    '';
  };

  # Collect agent templates for all files.
  vaultAgentTemplates = lib.concatLists (
    lib.mapAttrsToList (
      name: instance:
      lib.mapAttrsToList (
        fileName: fileCfg:
        let
          kv = kvPath name fileName fileCfg.secret;
          destPath = localPath name fileName fileCfg.secret;
        in
        {
          contents = ''{{- with secret "${cfg.mount}/data/${kv}" }}{{ .Data.data.content | base64Decode }}{{- end }}'';
          destination = destPath;
          perms = fileCfg.mode;
          command = "chown ${fileCfg.owner}:${fileCfg.group} ${destPath}";
        }
      ) instance.request.files
    ) flatInstances
  );
in
{
  options.services.vars-openbao = mkOption {
    description = ''
      OpenBao storage backend for vars.
      Secrets are generated locally and uploaded to an OpenBao KV v2 mount.
      At boot, a shared `openbao agent` fetches them into a tmpfs directory.
    '';
    type = submodule (vars-openbao: {
      options = {
        address = mkOption {
          description = "OpenBao server address (VAULT_ADDR compatible).";
          type = str;
          default = "http://127.0.0.1:8200";
        };

        tokenFile = mkOption {
          description = ''
            Path to a file containing the OpenBao token.
            For upload the token needs write access; for the agent
            fetch it only needs read access.
          '';
          type = str;
          default = "/run/keys/vars-openbao-token";
        };

        mount = mkOption {
          description = "KV v2 mount point in OpenBao.";
          type = str;
          default = "secret";
        };

        prefix = mkOption {
          description = "Path prefix within the KV mount for all vars entries.";
          type = str;
          default = "vars";
        };

        tmpDir = mkOption {
          description = ''
            Directory where fetched secrets are written at boot.
            Should be on a tmpfs so secrets are not persisted across reboots.
          '';
          type = str;
          default = "/run/vars";
        };

        agent = mkOption {
          description = ''
            Name of the `services.openbao.agents` entry whose `extraTemplates`
            this provider contributes its fetch templates to. The agent must be
            configured separately with authentication settings pointing at your
            OpenBao server (the systemd-openbaod broker ships the agent module).
          '';
          type = str;
          default = "default";
        };

        ${contract} = mkOption {
          description = "Instances of the varsBackend contract.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' =
              { name, request, ... }:
              {
                files = lib.mapAttrs (
                  fileName: fileCfg:
                  let
                    subdir = if fileCfg.secret then "secret" else "public";
                  in
                  {
                    path = "${vars-openbao.config.tmpDir}/${subdir}/${name}/${fileName}";
                  }
                ) request.files;
              };
          };
        };
      };
    });
  };

  config = {
    contracts.${contract}.providers.openbao.module = options.services.vars-openbao;

    systemd.services.upload-vars-openbao = lib.mkIf isSelected {
      description = "Upload generated vars to OpenBao";
      wantedBy = [ "multi-user.target" ];
      after = [
        "generate-vars.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${upload-vars}/bin/upload-vars-openbao";
      };
    };

    environment.systemPackages = lib.mkIf isSelected [ upload-vars ];

    # Contribute the fetch templates to the shared `openbao agent` via the
    # broker's `extraTemplates` merge point. The same agent renders both these
    # vars files and any per-service broker templates, so the host runs a single
    # agent. The templates carry no `changeAction`: they write the shared
    # `/run/vars/...` files once; reload-on-rotation is the per-service broker
    # layer's job.
    #
    # `extraTemplates` is derived only from `cfg.${contract}` (varsBackend
    # requests), never from `config.systemd.services`, so it cannot feed back
    # into the agent unit's name set (which `openbao-agent.nix` keeps
    # independent of the computed template to avoid recursion).
    services.openbao.agents.${cfg.agent}.extraTemplates = lib.mkIf isSelected vaultAgentTemplates;

    # The agent must wait for the upload so the KV paths exist before its first
    # render, and (via LoadCredential) get the token securely.
    systemd.services."openbao-agent-${cfg.agent}" = lib.mkIf isSelected {
      after = [ "upload-vars-openbao.service" ];
      wants = [ "upload-vars-openbao.service" ];
    };
  };
}
