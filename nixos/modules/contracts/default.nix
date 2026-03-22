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
            input = mkOption {
              description = "Input type of the ${name} contract.";
              type = optionType;
            };
            output = mkOption {
              description = "Output type of the ${name} contract.";
              type = optionType;
            };
            defaultProvider = mkOption {
              type = attrTag config.providerOptions;
            };
            instances = mkOption {
              type = attrsOf (attrsOf attrs);
              default =
                let
                  tag = (lib.unPair config.defaultProvider).name;
                in
                lib.getAttrFromPath (config.providerPaths.${tag} or [ "instances" ]) config.providerConfigs.${tag};
            };
            providerPaths = mkOption {
              default = { };
              type = attrsOf (listOf str);
            };
            providerOptions = mkOption {
              description = "Providers of the ${name} contract.";
              type = attrsOf option;
              default = { };
            };
            providerConfigs = mkOption {
              description = "Providers of the ${name} contract.";
              type = submodule {
                options = config.providerOptions;
              };
              default = { };
            };
            requests = mkOption {
              default = { };
              type = attrsOf (
                attrsOf (submodule {
                  options = {
                    input = mkOption {
                      type = config.input;
                    };
                    output = mkOption {
                      type = config.output;
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
    { input, output, ... }:
    {
      input = input { };
      output = output { };
    }
  ) lib.contracts;
}
