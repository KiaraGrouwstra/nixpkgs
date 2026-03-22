{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    attrTag
    listOf
    option
    optionType
    str
    submodule
    ;
in
{
  options.contracts = mkOption {
    default = { };
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        let
          inherit (config._module.args) name;
        in
        {
          options = {
            meta = mkOption {
              description = ''
                Useful information about contract ${name} and its maintenance.
              '';
              type = submodule {
                options = {
                  description = mkOption {
                    description = ''
                      Description of the contract.
                    '';
                    type = str;
                  };
                  maintainers = mkOption {
                    description = ''
                      Maintainers of the contract.
                    '';
                    type = listOf str;
                  };
                };
              };
            };
            interface = mkOption {
              default = { };
              type = submodule {
                options = {
                  input = mkOption {
                    description = "Input type of the ${name} contract.";
                    type = optionType;
                  };
                  output = mkOption {
                    description = "Output type of the ${name} contract.";
                    type = optionType;
                  };
                };
              };
            };
            defaultProvider = mkOption {
              type = attrTag (lib.mapAttrs (_: provider: provider.options) config.providers);
            };
            # FIXME figure out how to use these namespaces with modular services' multiple instantiations
            instances = mkOption {
              type = attrsOf (attrsOf attrs);
              default =
                let
                  tag = (lib.unPair config.defaultProvider).name;
                  inherit (config.providers.${tag}) path configuration;
                in
                lib.getAttrFromPath path configuration;
            };
            providers = mkOption {
              description = "Providers of the ${name} contract.";
              default = { };
              type = attrsOf (
                submodule (provider: {
                  options = {
                    path = mkOption {
                      type = listOf str;
                      default = [ "instances" ];
                    };
                    options = mkOption {
                      type = option;
                    };
                    configuration = mkOption {
                      inherit (provider.config.options) type default;
                    };
                  };
                })
              );
            };
            requests = mkOption {
              default = { };
              type = attrsOf (
                attrsOf (submodule {
                  options = {
                    input = mkOption {
                      type = config.interface.input;
                    };
                    output = mkOption {
                      type = config.interface.output;
                    };
                  };
                })
              );
            };
          };
        }
      )
    );
  };
  config.contracts = lib.mapAttrs (
    _:
    { meta, input, output, ... }:
    {
      inherit meta;
      interface = {
        input = input { };
        output = output { };
      };
    }
  ) lib.contracts;
}
