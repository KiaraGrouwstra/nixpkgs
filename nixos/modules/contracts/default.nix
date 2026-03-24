{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    listOf
    nullOr
    optionType
    raw
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
              type = nullOr raw;
              default = null;
              example = ''
                contract.config.providers."hardcoded-secret"
              '';
            };
            # FIXME figure out how to use these namespaces with modular services' multiple instantiations
            instances = mkOption {
              description = ''
                Instances of the contract.
                Structured like `."<service>"."<instance">.{ input; output; }`.
                Definition located at the provider's option navigated to according to
                `config.contracts."<contract>".providers."<provider>"`.
              '';
              type = attrsOf (attrsOf attrs);
              default =
                let
                  provider = contract.config.defaultProvider;
                in
                assert lib.assertMsg (provider != null) "contracts.${name}.defaultProvider is unset!";
                provider;
              defaultText = ''
                contract.config.providers.''${contract.config.defaultProvider}
              '';
            };
            providers = mkOption {
              description = ''
                Where to find instances of a provider of the ${name} contract that can take request inputs to return outputs.
              '';
              default = { };
              type = attrsOf raw;
            };
            requests = mkOption {
              description = ''
                Requests made by consumers of the contract, consisting of request inputs and the provider's returned outputs.
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
    {
      inherit meta;
      # get plain types here, so pass just `{ }` to `mkContract`
      interface = lib.mapAttrs (_: fn: fn { }) interface;
    }
  ) lib.contracts;
}
