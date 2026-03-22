{
  options,
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
  inherit (contracts.fileSecrets) interface;
  contract = "fileSecrets";
in
{
  options.testing.hardcoded-secret = mkOption {
    default = { };
    type = submodule (
      { config, ... }:
      {
        options = {
          directory = mkOption {
            type = str;
          };
          instances = mkOption {
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
                      input = mkOption {
                        description = "Input of the contract for file secrets.";
                        type = interface.input {
                          owner.default = "root";
                          group.default = "root";
                        };
                      };
                      output = mkOption {
                        description = "Output of the contract for file secrets.";
                        default = { };
                        type = interface.output {
                          path.default = "${config.directory}/${name}";
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
    testing.hardcoded-secret = (lib.unPair config.contracts.${contract}.defaultProvider).value // {
      instances = lib.contract.getInputs config.contracts.${contract};
    };
    contracts.${contract}.providers.hardcoded-secret = {
      inherit cfg;
      options = options.testing.hardcoded-secret;
    };

    system.activationScripts = lib.concatMapAttrs (
      namespace:
      mapAttrs' (
        n: cfg':
        let
          source = writeText "hardcodedsecret_${namespace}_${n}_content" cfg'.content;

          inherit (cfg') input output;
        in
        nameValuePair "hardcodedsecret_${namespace}_${n}" ''
          mkdir -p "$(dirname "${output.path}")"
          touch "${output.path}"
          chmod ${input.mode} "${output.path}"
          chown ${input.owner}:${input.group} "${output.path}"
          cp ${source} "${output.path}"
        ''
      )
    ) cfg.instances;
  };
}
