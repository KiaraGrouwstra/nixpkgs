{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-secret;
  opt = options.testing.hardcoded-secret;

  inherit (lib) mkOption;
  inherit (lib.types) str;
  inherit (pkgs) writeText;
in
{
  options.testing.hardcoded-secret = {
    directory = mkOption {
      type = str;
      default = "/run/hardcodedsecrets";
      description = ''
        Directory in which the provider writes the secret files.
        The path of each secret file in this directory is the path of its entry in
        [](#opt-testing.hardcoded-secret.fileSecrets), for example `stash/passwordFile`.
      '';
    };

    fileSecrets = mkOption {
      default = { };
      description = ''
        Hardcoded file secrets. These should only be used in tests.

        They aim to replace the usage of pkgs.writeText in NixOS VM tests
        as those make the file world readable
        while this module set runtime permissions on the file.
        This makes the tests more accurate, ensuring the permissions
        set by the contract consumer are correct.
      '';
      example = lib.literalExpression ''
        {
          myService.mySecret = {
            request = {
              owner = "me";
              group = "me";
              mode = "0400";
            };
            providerOptions.content = "My Secret";
          };
        }
      '';
      type = lib.contracts.fileSecrets.mkProviderType {
        overrides.request = {
          owner.default = "root";
          group.default = "root";
        };
        providerOptions.content = mkOption {
          type = str;
          description = ''
            Content of the secret as a string.

            This will be stored in the nix store and should only be used for testing or maybe in dev.
          '';
        };
        # The path of the entry in `fileSecrets`, for example `stash/passwordFile`.
        fulfill' =
          { loc, ... }:
          {
            path = "${cfg.directory}/${lib.concatStringsSep "/" (lib.drop (lib.length opt.fileSecrets.loc) loc)}";
          };
      };
    };
  };

  config = {
    # Fulfill the requests that the contracts system sends to this provider.
    testing.hardcoded-secret.fileSecrets =
      config.contracts.fileSecrets.providerRequests.hardcoded-secret;
    contracts.fileSecrets.providers.hardcoded-secret = cfg.fileSecrets;

    system.activationScripts = lib.concatMapNestedAttrs' opt.fileSecrets.type (
      path: cfg':
      let
        n = lib.concatStringsSep "_" path;
        source = writeText "hardcodedsecret_${n}_content" cfg'.providerOptions.content;

        inherit (cfg') request response;
      in
      {
        "hardcodedsecret_${n}" = ''
          mkdir -p "$(dirname "${response.path}")"
          touch "${response.path}"
          chmod ${request.mode} "${response.path}"
          chown ${request.owner}:${request.group} "${response.path}"
          cp ${source} "${response.path}"
        '';
      }
    ) cfg.fileSecrets;
  };
}
