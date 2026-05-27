# OpenBao varsBackend provider.
#
# After generate-vars produces files locally, the upload-vars-openbao service
# uploads them to an OpenBao KV v2 mount and removes the local copies.
# On subsequent boots vault-agent fetches the secrets from OpenBao into a
# tmpfs directory with the requested permissions.
#
# Requires:
# - A running OpenBao server
# - A vault-agent instance configured with authentication pointed at it
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

  # Local path where vault-agent writes fetched files (= provider result path).
  localPath =
    instanceName: fileName: secret:
    "${cfg.tmpDir}/${if secret then "secret" else "public"}/${instanceName}/${fileName}";

  # Flatten instances for iteration in runtime services. Key on the leaf
  # name to match what `fulfill'` sees: the contract framework passes the
  # deepest submodule key, not the joined path. `services.vars`'s
  # `generate-vars` writes through `backendFiles` using that same leaf
  # name, so keying here on `lib.last path` keeps all three sides
  # (generate, upload, fetch) agreeing on the same paths.
  flatInstances =
    lib.concatMapNestedAttrs' varsBackendType (
      path: instance: {
        ${lib.last path} = instance;
      }
    ) cfg.${contract};

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
                # unit activation, which can race vault-agent's first render
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

  # Collect vault-agent templates for all files.
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
      At boot, a vault-agent instance fetches them into a tmpfs directory.
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
            For upload the token needs write access; for the vault-agent
            fetch service it only needs read access.
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

        vaultAgentInstance = mkOption {
          description = ''
            Name of the `services.vault-agent.instances` entry to configure.
            The vault-agent instance must be configured separately with
            authentication settings pointing at your OpenBao server.
          '';
          type = str;
          default = "vars-openbao";
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

    # vault-agent fetches secrets from OpenBao at boot.
    services.vault-agent.instances.${cfg.vaultAgentInstance} = lib.mkIf isSelected {
      enable = true;
      package = lib.mkDefault pkgs.openbao;
      settings = {
        vault.address = cfg.address;
        template = vaultAgentTemplates;
      };
    };

    # LoadCredential for secure token delivery to vault-agent.
    systemd.services."vault-agent-${cfg.vaultAgentInstance}" = lib.mkIf isSelected {
      after = [ "upload-vars-openbao.service" ];
      serviceConfig.LoadCredential = [
        "token:${cfg.tokenFile}"
      ];
    };
  };
}
