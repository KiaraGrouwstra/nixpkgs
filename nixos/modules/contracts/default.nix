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
    description = ''
      Base option for a contract.

      To create a new contract, add an instance of `config.contracts.<name>`
      defining `meta` and `interface` options, or when adding to nixpkgs,
      adding one in `lib/contracts`.

      The `behaviorTest` option is used to ensure all `providers` of a contract
      behave the same way.

      Note that the split between lib.contracts and config.contracts ensures types
      would not have to depend on `config`, which would break the build of the manual.
    '';
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
                Useful information about the ${name} contract and its maintenance.
              '';
              type = submodule {
                options = {
                  description = mkOption {
                    description = ''
                      Description of the ${name} contract.
                    '';
                    type = str;
                  };
                  maintainers = mkOption {
                    description = ''
                      Maintainers of the ${name} contract.
                    '';
                    type = listOf str;
                  };
                };
              };
            };
            interface = mkOption {
              description = "Interface describing the types used in the ${name} contract.";
              default = { };
              type = submodule {
                options = {
                  input = mkOption {
                    description = "Input type of the ${name} contract.";
                    type = optionType;
                    default = submodule {
                      options = { };
                    };
                  };
                  output = mkOption {
                    description = "Output type of the ${name} contract.";
                    type = optionType;
                    default = submodule {
                      options = { };
                    };
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
                  inherit (config.providers.${tag}) path cfg;
                in
                lib.getAttrFromPath path cfg;
              defaultText = ''
                let
                  contract = config.contracts.<contract>;
                  tag = (lib.unPair contract.defaultProvider).name;
                  inherit (config.providers.''${tag}) path cfg;
                in
                lib.getAttrFromPath path cfg;
              '';
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
                      default = mkOption {
                        type = submodule {
                          options = { };
                        };
                        default = { };
                      };
                    };
                    cfg = mkOption {
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
    { meta, interface, ... }:
    let
      inherit (interface) input output;
    in
    {
      inherit meta;
      interface = {
        input = input { };
        output = output { };
      };
    }
  ) lib.contracts;
}
