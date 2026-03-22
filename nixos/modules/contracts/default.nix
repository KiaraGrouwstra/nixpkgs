{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    attrTag
    option
    optionType
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
            provider = mkOption {
            };
            providers = mkOption {
              description = "Providers of the ${name} contract.";
              type = attrsOf option;
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
