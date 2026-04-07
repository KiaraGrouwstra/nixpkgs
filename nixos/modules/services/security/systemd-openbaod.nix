# Provider for the fileSecrets contract using systemd-openbaod and vault-agent.
#
# Retrieves secrets from OpenBao via vault-agent templates and writes them to
# files on disk with the requested ownership and permissions.
#
# Requires:
# - A running OpenBao server
# - A vault-agent instance configured with authentication (e.g. AppRole, token)
#   pointed at the OpenBao server
#
# The provider generates vault-agent templates that render each secret to its
# result path, and activation scripts that set the correct file permissions.
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.services.systemd-openbaod;

  inherit (lib)
    contracts
    mkOption
    mkEnableOption
    mkPackageOption
    ;
  inherit (lib.types)
    nestedAttrsOf
    str
    submodule
    ;
  contract = "fileSecrets";
  inherit (contracts.${contract}) mkProviderType;
in
{
  options.services.systemd-openbaod = {
    enable = mkEnableOption "systemd-openbaod fileSecrets provider";

    package = mkPackageOption pkgs "systemd-openbaod" { };

    vaultAgentInstance = mkOption {
      type = str;
      default = "systemd-openbaod";
      description = ''
        Name of the `services.vault-agent.instances` entry to generate
        templates into. The vault-agent instance must be configured
        separately with authentication settings pointing at your
        OpenBao server.
      '';
    };

    ${contract} = mkOption {
      description = ''
        Instances of the fileSecrets contract fulfilled by systemd-openbaod.

        Each entry maps to a secret retrieved from OpenBao via vault-agent.
        The `openbaoPath` option specifies the Vault/OpenBao KV path and
        `openbaoField` selects which field to extract.
      '';
      type = mkProviderType {
        overrides.request = {
          owner.default = "root";
          group.default = "root";
        };
        providerOptions = {
          openbaoPath = mkOption {
            type = str;
            description = ''
              KV v2 path in OpenBao where this secret is stored
              (e.g. `"secret/data/myapp/password"`).
            '';
          };
          openbaoField = mkOption {
            type = str;
            default = "value";
            description = ''
              Field within the OpenBao secret's `.Data.data` to extract.
            '';
          };
        };
        fulfill' =
          { name, ... }:
          {
            path = "/run/systemd-openbaod/files/${name}";
          };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.systemd-openbaod.${contract} = config.contracts.${contract}.requests;
    contracts.${contract}.providers.systemd-openbaod.module = options.services.systemd-openbaod.${contract};

    # Generate vault-agent templates and activation scripts from flattened secrets.
    #
    # We flatten the nestedAttrsOf structure to iterate over leaf secrets,
    # generating a vault-agent template and an ownership fixup for each.
    services.vault-agent.instances.${cfg.vaultAgentInstance}.settings.template =
      let
        collectTemplates =
          prefix: attrs:
          lib.concatLists (
            lib.mapAttrsToList (
              name: value:
              let
                path = prefix ++ [ name ];
              in
              if value ? request && value ? result then
                [
                  {
                    contents = ''{{- with secret "${value.openbaoPath}" }}{{ .Data.data.${value.openbaoField} }}{{- end }}'';
                    destination = value.result.path;
                    perms = value.request.mode;
                    command = "chown ${value.request.owner}:${value.request.group} ${value.result.path}";
                  }
                ]
              else
                collectTemplates path value
            ) attrs
          );
      in
      collectTemplates [ ] cfg.${contract};

  };
}
