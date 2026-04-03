{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    enum
    nestedAttrsOf
    nullOr
    raw
    submodule
    ;
in
{
  options.contractTypes = mkOption {
    description = ''
      Types of contracts.
      For info on how to instantiate these, see `config.contracts`.

      To create a new contract type, add an instance of `config.contractTypes."<name>"`
      defining `meta` and `interface` options, or when adding to nixpkgs,
      preferably adding one in `lib/contracts`.
    '';
    # types are in `lib` as the docs build's sandbox has no `config`.
    type = attrsOf lib.contract.templateType;
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
          wantType = nestedAttrsOf (submodule {
            options = {
              request = mkOption {
                description = ''
                  The request parameters.
                  Must match the `${contractName}` contract interface's request type.
                '';
                type = submodule {
                  imports = interface.extraImports.request;
                  options = interface.request;
                };
              };
              result = mkOption {
                description = ''
                  Result returned to the request by the provider's side of the `${contractName}` contract.
                  Must match the `${contractName}` contract interface's result type.
                '';
                type = submodule {
                  imports = interface.extraImports.result;
                  options = interface.result;
                };
              };
            };
          });
        in
        mkOption {
          description = ''
            ${meta.description}

            Providers for the contract may be implemented by defining an option as follows:

            ```nix
            { lib, ... }:
            let
              inherit (lib.contracts.${contractName}) extend;
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
                        request = {
                          # options shared between any provider of the `${contractName}` contract
                          # "<attr>" = ...;
                        };
                        # provider-specific options:
                        # "<opt>" = ...;
                      };
                    }
                  ${"'"}';
                  type = lib.types.nestedAttrsOf (
                    lib.types.submodule (
                      { ... }:
                      {
                        options = {
                          request = lib.mkOption {
                            description = "Request of the `${contractName}` instance.";
                            type = extend.request {
                              # "<attr>".default = ...;
                            };
                          };
                          result = lib.mkOption {
                            description = "Result of the `${contractName}` instance.";
                            type = extend.result {
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
                      type = lib.contracts.${contractName}.mkContract {
                        request = {
                          # "<attr>".default = ...;
                        };
                      };
                    };
                  };
                  ```

                  **Providers (regular NixOS module):**

                  A plain NixOS module provider reads `contracts.${contractName}.requests`
                  and sets `contracts.${contractName}.providers.<name>` directly:

                  ```nix
                  services."<provider>".${contractName} = config.contracts.${contractName}.requests;
                  contracts.${contractName}.providers."<provider>" = config.services."<provider>".${contractName};
                  ```

                  **Providers (modular service):**

                  A modular service provider reads `contracts.${contractName}.requests` from
                  the `contracts` specialArg and sets `contract.providers.${contractName}`.
                  `nixos-contracts-bridge` automatically wires it into
                  `contracts.${contractName}.providers.<service>`:

                  ```nix
                  { lib, config, contracts ? { }, ... }:
                  {
                    _class = "service";
                    config = {
                      "<provider>".${contractName} = contracts.${contractName}.requests or { };
                      contract.providers.${contractName} = config."<provider>".${contractName};
                    };
                  }
                  ```
                '';
                type = wantType;
                default = { };
              };
              requests = mkOption {
                description = ''
                  Request data for the `${contractName}` contract, with `result` attributes filtered out.

                  Providers read from this option to get consumer requests.

                  Only canonical request options (those declared in `interface.request`) are included.
                  Deprecated aliases added via `interface.extraImports.request` are intentionally excluded.
                '';
                type = nestedAttrsOf raw;
                default = lib.mapNestedAttrs' wantType
                  (v: { request = lib.getAttrs (lib.attrNames interface.request) v.request; })
                  contract.config.want;
                defaultText = ''
                  lib.mapNestedAttrs' wantType
                    (v: { request = lib.getAttrs (lib.attrNames interface.request) v.request; })
                    contract.config.want
                '';
                readOnly = true;
              };
              providers = mkOption {
                description = ''
                  Where to find instances of a provider of the `${contractName}` contract that can take request inputs to return results.

                  For a regular NixOS module provider, set it directly:

                  ```nix
                  contracts.${contractName}.providers."<provider>" = config.services."<provider>".${contractName};
                  ```

                  For a modular service provider, set `contract.providers.${contractName}` on the service instead;
                  `nixos-contracts-bridge` will automatically register it here under the service's name:

                  ```nix
                  # in the service module:
                  contract.providers.${contractName} = config."<provider>".${contractName};
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

                  Note this options lacks `defaultProvider`'s graceful handling of contract renames.
                '';
                type = nullOr (enum (lib.attrNames contract.config.providers));
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
                    inherit (config.contracts.${contractName}.results."<consumer>") <instance>;
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
                        default.result = <instance>;
                        defaultText = ${"'"}'
                          { result = config.contracts.${contractName}.results."<consumer>"."<instance>"; }
                        ${"'"}';
                        type = ${contractName}.mkContract {
                          request = {
                            # "<attr>".default = ...;
                          };
                        };
                      };
                    };
                  }
                  ```
                '';
                type = nestedAttrsOf raw;
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
                  It mirrors `requests` which filters to just request data for providers.

                  Used in the consumer like:

                  ```nix
                  { lib, ... }:
                  let
                    inherit (lib.contracts) ${contractName};
                    inherit (config.contracts.${contractName}.results."<consumer>") <instance>;
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
                        default.result = <instance>;
                        defaultText = ${"'"}'
                          { result = config.contracts.${contractName}.results."<consumer>"."<instance>"; }
                        ${"'"}';
                        type = ${contractName}.mkContract {
                          request = {
                            # "<attr>".default = ...;
                          };
                        };
                      };
                    };
                  }
                  ```

                  **Modular Services:**

                  Read results the same way as regular NixOS modules:

                  ```nix
                  "<service>"."<request>".result =
                    config.contracts.${contractName}.results."<consumer>".''${name}."<request>";
                  ```

                  **Outstanding difference:** provider modular services still read consumer
                  requests via the `contracts` specialArg (not `config.contracts.${contractName}.requests`),
                  because each service's module system is evaluated in isolation — it can only
                  see `want` entries set within its own evaluation, not those of other services.
                  The containing system aggregates all services' wants and passes the result
                  back via the specialArg:

                  ```nix
                  { lib, config, contracts ? { }, ... }:
                  {
                    config."<provider>".${contractName} = contracts.${contractName}.requests or { };
                  }
                  ```
                '';
                type = nestedAttrsOf raw;
                default = lib.mapNestedAttrs' wantType
                  (v: v.result)
                  contract.config.instances;
                defaultText = ''
                  lib.mapNestedAttrs' wantType
                    (v: v.result)
                    config.contracts.${contractName}.instances
                '';
                readOnly = true;
              };
            };
          });
        }
      ) config.contractTypes;
    };
  };
}
