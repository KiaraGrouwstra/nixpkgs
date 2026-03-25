{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    enum
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
            providers = mkOption {
              description = ''
                Where to find instances of a provider of the ${name} contract that can take request inputs to return outputs.
              '';
              default = { };
              type = attrsOf raw;
            };
            defaultProviderName = mkOption {
              description = ''
                Select the name of the default provider to use for the contract.
                Useful as a way to configure `defaultProvider` more amenable to UI generation.

                Setting this for a contract means you no longer need to set providers for individual `instances`:

                ```nix
                contracts."<contract>".defaultProviderName = "<provider>";
                ```

                For an alternate way to set a default provider, consider `defaultProvider`.
              '';
              type = nullOr (enum (lib.attrNames contract.config.providers));
              default = null;
              example = ''
                "hardcoded-secret"
              '';
            };
            defaultProvider = mkOption {
              description = ''
                The default provider for the contract, alongside its configuration.

                For an alternate way to set a default provider, consider `defaultProviderName`.
              '';
              type = nullOr raw;
              default =
                let
                  inherit (contract.config) defaultProviderName;
                in
                if defaultProviderName == null then null else contract.config.providers.${defaultProviderName};
              defaultText = ''
                let
                  contract = config.contracts."<contract>";
                  inherit (contract) defaultProviderName;
                in
                if defaultProviderName == null then null else contract.providers.''${defaultProviderName}
              '';
              example = ''
                contract.config.providers."hardcoded-secret"
              '';
            };
            # FIXME figure out how to use these namespaces with modular services' multiple instantiations
            instances = mkOption {
              description = ''
                Instances of the contract.
                By default returns `defaultProvider`, if set (potentially by `defaultProviderName`),
                but may be overridden per instance like:

                ```nix
                contracts.fileSecrets.instances."testing"."mysecret" = config.contracts.fileSecrets.providers.hardcoded-secret;
                ```

                Content is structured like `."<service>"."<instance">.{ input; output; }`.
                Definition located at the provider's option navigated to according to
                `config.contracts."<contract>".providers."<provider>"`.
              '';
              # `type = attrsOf (attrsOf contract.config.interface);` breaks the docs build
              type = attrsOf (
                attrsOf (submodule {
                  options = {
                    input = mkOption {
                      description = "dummy input";
                      type = attrs;
                    };
                    output = mkOption {
                      description = "dummy output";
                      type = attrs;
                    };
                  };
                })
              );
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
