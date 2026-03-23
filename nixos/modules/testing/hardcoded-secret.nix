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
    description = ''
      Hardcoded file secrets. These should only be used in tests.

      They aim to replace the usage of pkgs.writeText in NixOS VM tests
      as those make the file world readable
      while this module set runtime permissions on the file.
      This makes the tests more accurate, ensuring the permissions
      set by the contract consumer are correct.
    '';
    default = { };
    type = submodule (
      hardcoded-secret:
      {
        options = {
          directory = mkOption {
            description = "The directory to store the secrets at.";
            type = str;
            example = "/run/hardcodedsecrets";
          };
          # FIXME if a service handling e.g. back-ups could act as a provider for multiple contracts,
          # how should that affect names of options like this? should they instead be named after the contract?
          instances = mkOption {
            description = ''
              Instances of the contract, including secret content and contract input/output.

              Matches the name of option `contracts."<contract>".instances`,
              which ends up referring to providers' options like this one.
            '';
            default = { };
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
    testing.hardcoded-secret = (lib.unPair config.contracts.${contract}.defaultProvider).value // {
      instances = lib.contract.getInputs config.contracts.${contract};
    };
    # FIXME here we manually assign a contract's provider a name.
    # could it make sense to instead just communicate path `[ "testing" "hardcoded-secret" ]`,
    # potentially short-cutting having to still pass `options.testing.hardcoded-secret`
    # and `config.testing.hardcoded-secret` as well?
    contracts.${contract}.providers.hardcoded-secret = {
      inherit cfg;
      opts = options.testing.hardcoded-secret;
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
