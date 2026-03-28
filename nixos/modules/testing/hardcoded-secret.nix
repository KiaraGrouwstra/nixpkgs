{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-secret;

  inherit (lib)
    contracts
    mapAttrs'
    mkOption
    nameValuePair
    ;
  inherit (lib.types)
    attrsOf
    str
    submodule
    ;
  inherit (pkgs) writeText;
  contract = "fileSecrets";
  inherit (contracts.${contract}) interface;
in
{
  options.testing.hardcoded-secret = mkOption {
    description = ''
      Hardcoded file secrets. These should only be used in tests.

      They aim to replace the usage of pkgs.writeText in NixOS VM tests
      as those make the file world readable
      while this module set runtime permissions on the file.
      This makes the tests more accurate, ensuring the permissions
      set by the contract consumer are correct.
    '';
    type = submodule (
      hardcoded-secret:
      {
        options = {
          directory = mkOption {
            description = "The directory to store the secrets at.";
            type = str;
            default = "/run/hardcodedsecrets";
          };
          ${contract} = mkOption {
            description = ''
              Instances of the fileSecrets contract, including secret content and contract input/output.
            '';
            example = lib.literalExpression ''
              {
                my.secret = {
                  input = {
                    user = "me";
                    mode = "0400";
                  };
                  content = "My Secret";
                };
              }
            '';
            type = attrsOf (
              attrsOf (
                submodule (
                  { name, ... }:
                  {
                    options = {
                      request = mkOption {
                        description = "Request of the contract for file secrets.";
                        type = interface.request {
                          owner.default = "root";
                          group.default = "root";
                        };
                      };
                      result = mkOption {
                        description = "Result of the contract for file secrets.";
                        default = { };
                        type = interface.result {
                          path = {
                            default = "${hardcoded-secret.config.directory}/${name}";
                            defaultText = ''
                              "''${hardcoded-secret.config.directory}/''${name}"
                            '';
                          };
                        };
                      };

                      content = mkOption {
                        type = str;
                        description = ''
                          Content of the secret as a string.

                          This will be stored in the nix store and should only be used for testing or maybe in dev.
                        '';
                      };
                    };
                  }
                )
              )
            );
          };
        };
      }
    );
  };

  config = {
    testing.hardcoded-secret.${contract} = config.contracts.${contract}.requests;
    contracts.${contract}.providers.hardcoded-secret = config.testing.hardcoded-secret.${contract};

    system.activationScripts = lib.concatMapAttrs (
      namespace:
      mapAttrs' (
        n: cfg':
        let
          source = writeText "hardcodedsecret_${namespace}_${n}_content" cfg'.content;

          inherit (cfg') request result;
        in
        nameValuePair "hardcodedsecret_${namespace}_${n}" ''
          mkdir -p "$(dirname "${result.path}")"
          touch "${result.path}"
          chmod ${request.mode} "${result.path}"
          chown ${request.owner}:${request.group} "${result.path}"
          cp ${source} "${result.path}"
        ''
      )
    ) cfg.${contract};
  };
}
