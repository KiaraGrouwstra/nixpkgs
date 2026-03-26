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
in
{
  options.contracts = mkOption {
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
                Useful information about the contract and its maintenance.
                Any `meta` defined in `lib.contracts` will be imported here.

                This may be used to define options in the provider:

                ```nix
                let
                  inherit (contracts) <contract>;
                in
                {
                  options = {
                    "<contract>" = lib.mkOption {
                      description = \'\'
                        Instances of contract <contract>, including contract input/output and provider-specific options.

                        Option `config.contracts."<contract>".instances` refers to providers' options like this one.
                      \'\';
                      example = lib.literalExpression \'\'
                        {
                          "<consumer>"."<instance>" = {
                            input = {
                              # options shared between any provider of the contract
                              # "<attr>" = ...;
                            };
                            # provider-specific options:
                            # "<opt>" = ...;
                          };
                        }
                      \'\';
                      type = lib.types.attrsOf (
                        lib.types.attrsOf (
                          lib.types.submodule (
                            { ... }:
                            {
                              options = {
                                input = lib.mkOption {
                                  description = "Input of the contract.";
                                  type = <contract>.interface.input {
                                    # "<attr>".default = ...;
                                  };
                                };
                                output = lib.mkOption {
                                  description = "Output of the contract.";
                                  type = <contract>.interface.output {
                                    # "<attr>".default = ...;
                                  };
                                };
                                # provider-specific options:
                                # "<opt>" = lib.mkOption {
                                #   type = lib.types."<type>";
                                #   description = \'\'
                                #     A provider-specific option.
                                #   \'\';
                                # };
                              };
                            }
                          )
                        )
                      );
                    };
                  };
                };
              }
              ```
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
              description = ''
                Interface describing the types used in the contract.
                Any defined in `lib.contracts` will be imported here.
              '';
              default = { };
              type = let
                type = optionType;
                default = submodule {
                  options = { };
                };
              in submodule {
                options = {
                  input = mkOption {
                    description = "Input type of the contract.";
                    inherit type default;
                  };
                  output = mkOption {
                    description = "Output type of the contract.";
                    inherit type default;
                  };
                };
              };
            };
            requests = mkOption {
              description = ''
                Requests made by consumers of the contract, consisting of
                request inputs and (once propagated back) the provider's returned outputs.

                This should be set in the consumer module:

                ```nix
                contracts.<contract>.requests.<consumer> = {
                  inherit (cfg) <request>;
                };
                ```

                A provider may use `lib.contract.getInputs to grab a contract's request inputs`
                to assign to its contract instances:

                ```nix
                services.<provider>.<contract> = lib.contract.getInputs config.contracts.<contract>;
                ```
              '';
              type = attrsOf (
                attrsOf (submodule {
                  options = {
                    input = mkOption {
                      description = ''
                        The request's input parameters.
                        Must match the contract interface's input type.
                      '';
                      type = contract.config.interface.input;
                    };
                    output = mkOption {
                      description = ''
                        Output returned to the request by the provider's side of the contract.
                        Must match the contract interface's output type.
                      '';
                      type = contract.config.interface.output;
                    };
                  };
                })
              );
            };
            providers = mkOption {
              description = ''
                Where to find instances of a provider of the contract that can take request inputs to return outputs.

                It is set in the provider:

                ```nix
                contracts."<contract>".providers."<provider>" = config.services."<provider>"."<contract>";
                ```

                It may then be used where you configure the service consuming the contract to manually set a provider:

                ```nix
                contracts."<contract>".instances."<consumer>"."<instance>" = config.contracts."<contract>".providers."<provider>";
                ```

                For an easier way to set providers, consider setting `defaultProviderName` or `defaultProvider`.
              '';
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
              # default = null;
              example = ''
                "hardcoded-secret"
              '';
            };
            defaultProvider = mkOption {
              description = ''
                The default provider for the contract, alongside its configuration.

                Setting this for a contract means you no longer need to set providers for individual `instances`:

                ```nix
                contracts."<contract>".defaultProvider = config.contracts."<contract>".providers."<provider>";
                ```

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
                contracts."<contract>".instances."<consumer>"."<instance>" = config.contracts."<contract>".providers."<provider>";
                ```

                Used in the consumer like:

                ```nix
                let
                  inherit (contracts) <contract>;
                  inherit (config.contracts."<contract>".instances."<consumer>") <instance>;
                in
                {
                  options = {
                    "<instance>" = lib.mkOption {
                      description = \'\'
                        An instance of contract <contract>.
                        Attributes of the contract's output type may be accessed in its `.output` attribute.
                        Information specific to the provider may be set like:

                        ```nix
                        services."<provider>"."<contract>"."<consumer>"."<instance>"."<attr>" = ...;
                        ```
                      \'\';
                      default = { inherit (<instance>) output; };
                      defaultText = \'\'
                        { inherit (config.contracts."<contract>".instances."<consumer>"."<instance>") output; }
                      \'\';
                      type = lib.types.submodule {
                        options = {
                          input = lib.mkOption {
                            description = "Input of the contract.";
                            default = { };
                            type = <contract>.interface.input {
                              # "<attr>".default = ...;
                            };
                          };
                          output = lib.mkOption {
                            description = "Output of the contract.";
                            type = <contract>.interface.output { };
                          };
                        };
                      };
                    };
                  };
                }
                ```

                Using the `instances` through such options ensures request input propagation.

                Content is structured like `."<service>"."<instance">.{ input; output; }`.
                Definition located at the provider's option navigated to according to
                `config.contracts."<contract>".providers."<provider>"`.
              '';
              # `type = attrsOf (attrsOf contract.config.interface);` breaks the docs build
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
