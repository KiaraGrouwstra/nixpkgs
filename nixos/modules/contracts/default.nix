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
    option
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
                type = attrsOf option;
                default = { };
              in
              submodule {
                options = {
                  request = mkOption {
                    description = "Request type of the contract.";
                    inherit type default;
                  };
                  result = mkOption {
                    description = "Result type of the contract.";
                    inherit type default;
                  };
                };
              };
          };
          mkContract = mkOption {
            description = ''
              Augment the contract interface's type using a set of overrides.

              contract.mkContract :: attrs -> optionType

              # Inputs

              `overrides`

              : 1\. A (recursive) attrset of fields to add to the contract interface submodule type

              Example:

              ```nix
              { config, lib, ... }:
              let
                inherit (lib) mkOption contract types;
              in
              {
                options.foo = mkOption {
                  default = { };
                  type = config.contractType."<contract>".mkContract
                    {
                      bar = {
                        default = 10;
                        defaultText = "10";
                      };
                    }
                };
              }
              ```
            '';
            type = functionTo optionType;
            readOnly = true;
            default =
              overrides:
              lib.extendSubmodule overrides (submodule {
                options = lib.mapAttrs (
                  _: options: mkOption { type = submodule { inherit options; }; }
                ) contract.config.interface;
              });
          };
          extend = mkOption {
            description = ''
              Construct a type for a provider's individual request or result option, with overrides applied.

              `extend.request overrides` and `extend.result overrides` produce types for the respective interface parts.
            '';
            type = attrsOf (functionTo optionType);
            readOnly = true;
            default = lib.mapAttrs (
              _: options: overrides:
              lib.extendSubmodule overrides (lib.types.submodule { inherit options; })
            ) contract.config.interface;

          };
          behaviorTest = mkOption {
            description = ''
              Test used to ensure all `providers` of the contract behave the same way.

              For an example of how to write a test for a contract,
              see the `behaviorTest` in `lib/contracts/file-secrets.nix`.
            '';
            # The type should be more precise of course.
            # There should actually be a NixOSTest type.
            # And we can probably do something fancy with the `request` and `result` modules.
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
                    Instances of contract `${contractName}`, including contract request/result and provider-specific options.

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
                            request = lib.mkOption {
                              description = "Request of the `${contractName}` instance.";
                              type = ${contractName}.interface.request {
                                # "<attr>".default = ...;
                              };
                            };
                            result = lib.mkOption {
                              description = "Result of the `${contractName}` instance.";
                              type = ${contractName}.interface.result {
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
              want = mkOption {
                description = ''
                  Request declared by consumers of the `${contractName}` contract, consisting of
                  request inputs and (once propagated back) the provider's returned results.

                  This should be set in the consumer module.

                  **Regular NixOS Modules:**

                  If the consumer is a regular NixOS module, set `want` directly:

                  ```nix
                  let
                    cfg = config.services."<consumer>";
                  in
                  # options.services.<consumer> = ...;
                  config = {
                    contracts.${contractName}.want."<consumer>" = {
                      inherit (cfg) <request>;
                    };
                  };
                  ```

                  Then consume the results in your service options:

                  ```nix
                  options.services."<consumer>" = {
                    "<request>" = lib.mkOption {
                      description = "...";
                      default = { };
                      type = lib.types.submodule {
                        options = {
                          request = lib.mkOption {
                            type = ${contractName}.interface.request { };
                          };
                          result = lib.mkOption {
                            type = ${contractName}.interface.result { };
                          };
                        };
                      };
                    };
                  };
                  ```

                  **Modular Services:**

                  If the consumer is a [modular service](#modular-services), use `contractRequests`
                  and the helper functions from `lib.contract`:

                  ```nix
                  {
                    lib,
                    config,
                    contracts ? { },
                    ...
                  }:
                  let
                    cfg = config."<consumer>";
                    contractOptions.${contractName} = [ "<request1>" "<request2>" ];
                  in
                  {
                    # Define contract option in your service options
                    options."<consumer>" = {
                      "<request>" = lib.mkOption {
                        description = "...";
                        default = { };
                        type = lib.types.submodule {
                          options = {
                            request = lib.mkOption {
                              type = ${contractName}.interface.request { };
                            };
                            result = lib.mkOption {
                              type = ${contractName}.interface.result { };
                            };
                          };
                        };
                      };
                    };

                    config = {
                      contractRequests = lib.contract.mkRequests "<consumer>" contractOptions config;
                      "<consumer>" = { }
                        // lib.contract.mkResults "<consumer>" contractOptions contracts;
                    };
                  }
                  ```

                  The helpers `lib.contract.mkRequests` and `lib.contract.mkResults` automatically
                  handle the wiring for all contract options listed in `contractOptions`.

                  **Providers:**

                  A provider module uses `contracts.${contractName}.requests` to grab
                  the contract's request data (with `result`s filtered out):

                  ```nix
                  services."<provider>".${contractName} = config.contracts.${contractName}.requests;
                  ```
                '';
                type = attrsOf (
                  attrsOf (submodule {
                    options = {
                      request = mkOption {
                        description = ''
                          The request parameters.
                          Must match the `${contractName}` contract interface's request type.
                        '';
                        type = submodule { options = interface.request; };
                      };
                      result = mkOption {
                        description = ''
                          Result returned to the request by the provider's side of the `${contractName}` contract.
                          Must match the `${contractName}` contract interface's result type.
                        '';
                        type = submodule { options = interface.result; };
                      };
                    };
                  })
                );
              };
              requests = mkOption {
                description = ''
                  Request data for the `${contractName}` contract, with `result` attributes filtered out.

                  Providers read from this option to get consumer requests.
                '';
                type = attrsOf (attrsOf attrs);
                default = lib.mapAttrs (_: lib.mapAttrs (_: lib.getAttrs [ "request" ])) contract.config.want;
                defaultText = ''
                  lib.mapAttrs (
                    _: lib.mapAttrs (_: lib.getAttrs [ "request" ])
                  ) contract.config.want
                '';
                readOnly = true;
              };
              providers = mkOption {
                description = ''
                  Where to find instances of a provider of the `${contractName}` contract that can take request inputs to return results.

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
                  in
                  {
                    options = {
                      "<instance>" = lib.mkOption {
                        description = ${"'"}'
                          An instance of contract `${contractName}`.
                          See `contracts.${contractName}.want.<name>.<name>.result`
                          for documentation on the type of its `.result` attribute.
                          Information specific to the provider may be set like:

                          ```nix
                          services."<provider>".${contractName}."<consumer>"."<instance>"."<attr>" = ...;
                          ```
                        ${"'"}';
                        default = {
                          result = config.contracts.${contractName}.results."<consumer>"."<instance>";
                        };
                        defaultText = ${"'"}'
                          { result = config.contracts.${contractName}.results."<consumer>"."<instance>"; }
                        ${"'"}';
                        type = lib.types.submodule {
                          options = {
                            request = lib.mkOption {
                              description = "Request of the `${contractName}` instance.";
                              default = { };
                              type = ${contractName}.interface.request {
                                # "<attr>".default = ...;
                              };
                            };
                            result = lib.mkOption {
                              description = "Result of the `${contractName}` instance.";
                              type = ${contractName}.interface.result { };
                            };
                          };
                        };
                      };
                    };
                  }
                  ```

                  Using `results` through such options ensures request input propagation.

                  **Modular Services:**

                  In [modular services](#modular-services), `config.contracts` is not available.
                  Instead, access the `contracts` specialArg from the service module parameters:

                  ```nix
                  {
                    lib,
                    config,
                    options,
                    contracts ? { },
                    ...
                  }:
                  ```

                  Use the `lib.contract.mkResults` helper to automatically inject contract
                  results into your service options:

                  ```nix
                  let
                    contractOptions.${contractName} = [ "<request1>" "<request2>" ];
                  in
                  {
                    config = {
                      "<service>" = { }
                        // lib.contract.mkResults "<service>" contractOptions contracts;
                    };
                  }
                  ```

                  The helper will automatically populate the `result` attribute of each
                  contract option from the fulfilled contract instances.

                  Content in `contracts` is structured like `."<service>"."<instance">.{ request; result; }`.
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
              results = mkOption {
                description = ''
                  Result data for the `${contractName}` contract, with `request` attributes filtered out.

                  This is a read-only calculated option that extracts just the result values from fulfilled contracts.
                  It mirrors `inputs` which filters to just request data for providers.

                  Used in the consumer like:

                  ```nix
                  cfg."<instance>".result = config.contracts.${contractName}.results."<consumer>"."<instance>";
                  ```
                '';
                type = attrsOf (attrsOf attrs);
                default = lib.mapAttrs (_: lib.mapAttrs (_: v: v.result)) contract.config.instances;
                defaultText = ''
                  lib.mapAttrs (
                    _: lib.mapAttrs (_: v: v.result)
                  ) config.contracts.${contractName}.instances
                '';
                readOnly = true;
              };
            };
          });
        }
      ) config.contractTypes;
    };
  };
  config.contractTypes = lib.contracts;
}
