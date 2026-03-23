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
  empty = submodule {
    options = { };
  };
in
{
  options.contracts = mkOption {
    default = { };
    description = ''
      Base option for a contract.

      To create a new contract, add an instance of `config.contracts."<name>"`
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
                    default = empty;
                  };
                  output = mkOption {
                    description = "Output type of the ${name} contract.";
                    type = optionType;
                    default = empty;
                  };
                };
              };
            };
            defaultProvider = mkOption {
              description = ''
                The default provider for the contract, alongside its configuration.
              '';
              type = attrTag (lib.mapAttrs (_: provider: provider.opts) config.providers);
              example = ''
                {
                  hardcoded-secret = {
                    directory = "/run/hardcodedsecrets";
                  };
                }
              '';
            };
            # FIXME figure out how to use these namespaces with modular services' multiple instantiations
            instances = mkOption {
              description = ''
                Instances of the contract.
                Structured like `."<service>"."<instance">.{ input; output; }`.
                Definition located at the provider's option navigated to according to
                `config.contracts."<contract>".providers."<provider>".path`.
              '';
              type = attrsOf (attrsOf attrs);
              default =
                let
                  tag = (lib.unPair config.defaultProvider).name;
                  inherit (config.providers.${tag}) path cfg;
                in
                lib.getAttrFromPath path cfg;
              defaultText = ''
                let
                  contract = config.contracts."<contract>";
                  tag = (lib.unPair contract.defaultProvider).name;
                  inherit (config.providers.''${tag}) path cfg;
                in
                lib.getAttrFromPath path cfg;
              '';
            };
            providers = mkOption {
              description = ''
                Providers of the ${name} contract that can take request inputs to return outputs.
              '';
              default = { };
              type = attrsOf (
                submodule (provider: {
                  options = {
                    path = mkOption {
                      description = ''
                        A path to navigate from the provider to its instances of the contract.
                      '';
                      type = listOf str;
                      default = [ "instances" ];
                    };
                    opts = mkOption {
                      description = ''
                        The `options` of the provider.

                        To avoid confusion, the name used here is made distinct from `options`.
                      '';
                      type = option;
                      default = mkOption {
                        type = empty;
                        default = { };
                      };
                    };
                    cfg = mkOption {
                      description = ''
                        The `config` of the provider, often denoted by `cfg`.
                      '';
                      inherit (provider.config.opts) type default;
                    };
                  };
                })
              );
            };
            requests = mkOption {
              description = ''
                Requests made by consumers of the contract, consisting of request inputs then the provider's returned outputs.
              '';
              default = { };
              type = attrsOf (
                attrsOf (submodule {
                  options = {
                    input = mkOption {
                      description = ''
                        The request's input parameters.
                        Must match the ${name} contract interface's input type.
                      '';
                      type = config.interface.input;
                    };
                    output = mkOption {
                      description = ''
                        Output returned to the request by the provider's side of the contract.
                        Must match the ${name} contract interface's output type.
                      '';
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
