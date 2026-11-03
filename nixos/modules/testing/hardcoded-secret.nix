{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-secret;

  inherit (lib) concatStringsSep mkOption;
  inherit (lib.types)
    nestedAttrsOf
    str
    submodule
    ;
  inherit (pkgs) writeText;

  # This provider in `contracts.fileSecrets.providers`.
  provider = config.contracts.fileSecrets.providers.hardcoded-secret;
  # The type of `contracts.fileSecrets.instances`, to find its entries.
  instancesType = (options.contracts.fileSecrets.type.getSubOptions [ ]).instances.type;
in
{
  options.testing.hardcoded-secret.directory = mkOption {
    type = str;
    default = "/run/hardcodedsecrets";
    description = ''
      Directory in which the provider writes the secret files.
      Each secret file has the path of its entry in
      [](#opt-contracts.fileSecrets.instances),
      for example `stash/password` for `instances.stash.password`.
    '';
  };

  options.contracts.fileSecrets.instances = mkOption {
    type = nestedAttrsOf (
      submodule (
        { instancePath, ... }:
        {
          options.providerOptions.hardcoded-secret = mkOption {
            description = ''
              Options of the provider `testing.hardcoded-secret` for this entry.
              This provider should only be used in tests.

              It aims to replace the usage of pkgs.writeText in NixOS VM tests
              as those make the file world readable
              while this module set runtime permissions on the file.
              This makes the tests more accurate, ensuring the permissions
              set by the contract consumer are correct.

              A service writes `content` to `response.path`,
              with the `mode`, `owner` and `group` from `request`.
              The service runs after `systemd-sysusers` or `userborn`, and before `sysinit.target`,
              thus the file exists before the services that use it start.
              The content is also in the Nix store, where each user can read it.
            '';
            default = { };
            type = submodule {
              options.content = mkOption {
                type = str;
                description = ''
                  Content of the secret as a string.

                  This will be stored in the nix store and should only be used for testing or maybe in dev.
                '';
              };
            };
          };
          config.response = lib.mkIf (lib.hasAttrByPath instancePath provider.instances) (
            lib.mkOptionDefault { path = "${cfg.directory}/${concatStringsSep "/" instancePath}"; }
          );
        }
      )
    );
  };

  config = {
    contracts.fileSecrets.providers.hardcoded-secret = { };

    # Write each secret in a service and not in an activation script.
    # An activation script can run before the owner of the secret exists:
    # activation scripts without dependencies run in alphabetical order,
    # and `systemd-sysusers` and `userborn` create users after activation.
    # The services run before `sysinit.target`, thus before all services
    # that have default dependencies, such as the consumers of the secrets.
    systemd.services = lib.concatMapNestedAttrs' instancesType (
      path: instance:
      let
        n = concatStringsSep "_" path;
        source = writeText "hardcodedsecret_${n}_content" instance.providerOptions.hardcoded-secret.content;

        inherit (instance) request response;
      in
      {
        "hardcodedsecret_${n}" = {
          description = "Hardcoded secret ${lib.showAttrPath path}";
          wantedBy = [ "sysinit.target" ];
          after = [
            "local-fs.target"
            "systemd-sysusers.service"
            "userborn.service"
          ];
          before = [
            "sysinit.target"
            "shutdown.target"
          ];
          conflicts = [ "shutdown.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -D -m ${request.mode} -o ${request.owner} -g ${request.group} \
              ${source} "${response.path}"
          '';
        };
      }
    ) provider.instances;
  };
}
