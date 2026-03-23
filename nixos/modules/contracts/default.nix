{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
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
        contract:
        let
          inherit (contract.config._module.args) name;
        in
        {
          options = {
            meta = mkOption {
              description = ''
                Useful information about the ${name} contract and its maintenance.

                Note that, while `meta` is already a valid module attribute next to `config` and `options`,
                it is added as an explicit configuration option here to facilitate transferring this info from `lib.contracts`.
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
            # FIXME how to override this for specific instances of the contract?
            defaultProvider = mkOption {
              description = ''
                The default provider for the contract, alongside its configuration.
              '';
              type = types.enum (lib.attrNames contract.config.providers);
              example = ''
                "hardcoded-secret"
              '';
            };
            # FIXME figure out how to use these namespaces with modular services' multiple instantiations
            instances = mkOption {
              description = ''
                Instances of the contract.
                Structured like `."<service>"."<instance">.{ input; output; }`.
                Definition located at the provider's option navigated to according to
                `config.contracts."<contract>".providers."<provider>".path`.

                As such, a dependent type here, unfortunately breaking docs, would be:

                ```nix
                  let
                    tag = contract.config.defaultProvider;
                  in
                  lib.getAttrFromPath contract.config.providerPaths.''${tag} contract.config.providerOptions.''${tag};
                ````
              '';
              type = attrsOf (attrsOf attrs);
              default =
                let
                  inherit (contract.config.providers.${contract.config.defaultProvider}) path space;
                in
                lib.getAttrFromPath (space ++ path) config;
              defaultText = ''
                let
                  inherit (contract.config.providers.''${contract.config.defaultProvider}) path space;
                in
                lib.getAttrFromPath (space ++ path) config;
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
                    # FIXME could we settle for a static path? if so, could we ditch this support for these custom option paths?
                    path = mkOption {
                      description = ''
                        A path to navigate from the provider to its instances of the contract.
                      '';
                      type = listOf str;
                      default = [ "instances" ];
                    };
                    space = mkOption {
                      description = ''
                        Where to find the module.
                      '';
                      type = listOf str;
                      default = [ ];
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
                      type = contract.config.interface.input;
                    };
                    output = mkOption {
                      description = ''
                        Output returned to the request by the provider's side of the contract.
                        Must match the ${name} contract interface's output type.
                      '';
                      type = contract.config.interface.output;
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
