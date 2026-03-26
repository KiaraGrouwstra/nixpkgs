{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    enum
    functionTo
    listOf
    nullOr
    optionType
    raw
    str
    submodule
    ;
in
{
  meta.buildDocsInSandbox = false;

  options.contractTypes = mkOption {
    description = ''
      Types of contracts.
      For info on how to instantiate these, see `config.contracts`.

      To create a new contract type, add an instance of `config.contractTypes."<name>"`
      defining `meta` and `interface` options, or when adding to nixpkgs,
      preferably adding one in `lib/contracts`.
    '';
    type = attrsOf (
      submodule (contract: {
        options = {
          meta = mkOption {
            description = ''
              Useful information about the contract and its maintenance.
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
                  type = listOf attrs;
                };
              };
            };
          };
          interface = mkOption {
            description = ''
              Interface describing the types used in the contract.
            '';
            default = { };
            type =
              let
                type = optionType;
                default = submodule {
                  options = { };
                };
                defaultText = ''
                  submodule { options = { }; }
                '';
              in
              submodule {
                options = {
                  input = mkOption {
                    description = "Input type of the contract.";
                    inherit type default defaultText;
                  };
                  output = mkOption {
                    description = "Output type of the contract.";
                    inherit type default defaultText;
                  };
                };
              };
          };
          behaviorTest = mkOption {
            description = ''
              Test used to ensure all `providers` of the contract behave the same way.

              For an example of how to write a test for a contract,
              see the `behaviorTest` in `lib/contracts/file-secrets.nix`.
            '';
            # The type should be more precise of course.
            # There should actually be a NixOSTest type.
            # And we can probably do something fancy with the `input` and `output` modules.
            type = functionTo attrs;
            default =
              {
                name,
                extraModules ? [ ],
              }:
              {
                name = "contracts_<contract>_${name}";
                containers.machine =
                  { ... }:
                  {
                    imports = extraModules;
                  };
                testScript =
                  { ... }:
                  ''
                    machine.succeed("echo 'please define a test!' >&2; exit 1")
                  '';
              };
            defaultText = ''
              {
                name,
                extraModules ? [ ],
              }:
              {
                name = "contracts_<contract>_''${name}";
                containers.machine =
                  { ... }:
                  {
                    imports = extraModules;
                  };
                testScript = { ... }: "";
              }
            '';
          };
        };
      })
    );
  };
  options.contracts = mkOption {
    description = ''
      Base option for a contract.
    '';
    type = submodule {
      options = lib.mapAttrs (
        contractName: contractType:
        let
          inherit (contractType) meta interface;
        in
        mkOption {
          description = ''
            ${meta.description}

            Providers for the contract may be implemented by defining an option as follows:

            ```nix
            { lib, ... }:
            let
              inherit (lib.contracts) ${contractName};
            in
            {
              options = {
                ${contractName} = lib.mkOption {
                  description = ${"'"}'
                    Instances of contract `${contractName}`, including contract input/output and provider-specific options.

                    Option `config.contracts.${contractName}.instances` refers to providers' options like this one.
                  ${"'"}';
                  example = ${"'"}'
                    {
                      "<consumer>"."<instance>" = {
                        input = {
                          # options shared between any provider of the `${contractName}` contract
                          # "<attr>" = ...;
                        };
                        # provider-specific options:
                        # "<opt>" = ...;
                      };
                    }
                  ${"'"}';
                  type = lib.types.attrsOf (
                    lib.types.attrsOf (
                      lib.types.submodule (
                        { ... }:
                        {
                          options = {
                            input = lib.mkOption {
                              description = "Input of the `${contractName}` instance.";
                              type = ${contractName}.interface.input {
                                # "<attr>".default = ...;
                              };
                            };
                            output = lib.mkOption {
                              description = "Output of the `${contractName}` instance.";
                              type = ${contractName}.interface.output {
                                # "<attr>".default = ...;
                              };
                            };
                            # provider-specific options:
                            # "<opt>" = lib.mkOption {
                            #   type = lib.types."<type>";
                            #   description = ${"'"}'
                            #     A provider-specific option.
                            #   ${"'"}';
                            # };
                          };
                        }
                      )
                    )
                  );
                };
              };
            }
            ```
          '';
          type = submodule (contract: {
            options = {
              requests = mkOption {
                description = ''
                  Requests made by consumers of the `${contractName}` contract, consisting of
                  request inputs and (once propagated back) the provider's returned outputs.

                  This should be set in the consumer module:

                  ```nix
                  let
                    cfg = services."<consumer>";
                  in
                  # options.services.<consumer> = ...;
                  config = {
                    contracts.${contractName}.requests."<consumer>" = {
                      inherit (cfg) <request>;
                    };
                  };
                  ```

                  A provider module may use `lib.contract.getInputs` to grab a
                  contract's request `input`s to assign to its contract instances:

                  ```nix
                  services."<provider>".${contractName} = lib.contract.getInputs config.contracts.${contractName};
                  ```
                '';
                type = attrsOf (
                  attrsOf (submodule {
                    options = {
                      input = mkOption {
                        description = ''
                          The request's input parameters.
                          Must match the `${contractName}` contract interface's input type.
                        '';
                        type = interface.input;
                      };
                      output = mkOption {
                        description = ''
                          Output returned to the request by the provider's side of the `${contractName}` contract.
                          Must match the `${contractName}` contract interface's output type.
                        '';
                        type = interface.output;
                      };
                    };
                  })
                );
              };
              providers = mkOption {
                description = ''
                  Where to find instances of a provider of the `${contractName}` contract that can take request inputs to return outputs.

                  It is set in the provider:

                  ```nix
                  contracts.${contractName}.providers."<provider>" = config.services."<provider>".${contractName};
                  ```

                  It may then be used where you configure the service consuming the `${contractName}` contract to manually set a provider:

                  ```nix
                  contracts.${contractName}.instances."<consumer>"."<instance>" = config.contracts.${contractName}.providers."<provider>";
                  ```

                  For an easier way to set providers, consider setting `defaultProviderName` or `defaultProvider`.
                '';
                type = attrsOf raw;
              };
              defaultProviderName = mkOption {
                description = ''
                  Select the name of the default provider to use for the `${contractName}` contract.
                  Useful as a way to configure `defaultProvider` more amenable to UI generation.

                  Setting this for a contract means you no longer need to set providers for individual `instances`:

                  ```nix
                  contracts.${contractName}.defaultProviderName = "<provider>";
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
                  The default provider for the `${contractName}` contract, alongside its configuration.

                  Setting this for a contract means you no longer need to set providers for individual `instances`:

                  ```nix
                  contracts.${contractName}.defaultProvider = config.contracts.${contractName}.providers."<provider>";
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
                    contract = config.contracts.${contractName};
                    inherit (contract) defaultProviderName;
                  in
                  if defaultProviderName == null then null else contract.providers.''${defaultProviderName}
                '';
                example = ''
                  config.contracts.fileSecrets.providers.hardcoded-secret
                '';
              };
              # FIXME figure out how to use these namespaces with modular services' multiple instantiations
              instances = mkOption {
                description = ''
                  Instances of the `${contractName}` contract.
                  By default returns `defaultProvider`, if set (potentially by `defaultProviderName`),
                  but may be overridden per instance like:

                  ```nix
                  contracts.${contractName}.instances."<consumer>"."<instance>" = config.contracts.${contractName}.providers."<provider>";
                  ```

                  Used in the consumer like:

                  ```nix
                  { lib, ... }:
                  let
                    inherit (lib.contracts) ${contractName};
                    inherit (config.contracts.${contractName}.instances."<consumer>") <instance>;
                  in
                  {
                    options = {
                      "<instance>" = lib.mkOption {
                        description = ${"'"}'
                          An instance of contract `${contractName}`.
                          See `contracts.${contractName}.requests.<name>.<name>.output`
                          for documentation on the type of its `.output` attribute.
                          Information specific to the provider may be set like:

                          ```nix
                          services."<provider>".${contractName}."<consumer>"."<instance>"."<attr>" = ...;
                          ```
                        ${"'"}';
                        default = { inherit (<instance>) output; };
                        defaultText = ${"'"}'
                          { inherit (config.contracts.${contractName}.instances."<consumer>"."<instance>") output; }
                        ${"'"}';
                        type = lib.types.submodule {
                          options = {
                            input = lib.mkOption {
                              description = "Input of the `${contractName}` instance.";
                              default = { };
                              type = ${contractName}.interface.input {
                                # "<attr>".default = ...;
                              };
                            };
                            output = lib.mkOption {
                              description = "Output of the `${contractName}` instance.";
                              type = ${contractName}.interface.output { };
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
                  `config.contracts.${contractName}.providers."<provider>"`.
                '';
                # `type = attrsOf (attrsOf interface);` breaks the docs build
                type = attrsOf (attrsOf attrs);
                default =
                  let
                    provider = contract.config.defaultProvider;
                  in
                  assert lib.assertMsg (provider != null) "contracts.${contractName}.defaultProvider is unset!";
                  provider;
                defaultText = ''
                  config.contracts.${contractName}.defaultProvider
                '';
              };
            };
          });
        }
      ) config.contractTypes;
    };
  };
  config.contractTypes = lib.mapAttrs (
    _:
    {
      meta,
      interface,
      behaviorTest,
      ...
    }:
    {
      inherit meta behaviorTest;
      # get plain types here, so pass just `{ }` to `mkContract`
      interface = lib.mapAttrs (_: fn: fn { }) interface;
    }
  ) lib.contracts;
}
