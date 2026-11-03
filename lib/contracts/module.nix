# Contracts module: routes requests from consumers to providers.
#
# This module does not depend on NixOS, so other module systems can import it.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    contractTypes = mkOption {
      description = ''
        Contract types that consumers and providers can use.

        Each contract type has an `interface`: a module with the options
        `request` and `response`.
        Consumers and providers import this module into their submodule types.

        The contract types of nixpkgs are in `lib.contracts`.
        To add a contract type to nixpkgs, add a file in `lib/contracts/definitions/`.
        To add a contract type outside of nixpkgs, set it in this option.

        **Use contracts in a different module system:**

        1\. Import `lib.contract.module`.

        2\. Set this option to `lib.contracts`, so that the contract types of nixpkgs are available.

        The NixOS module `nixos/modules/contracts/default.nix` does these two steps.
      '';
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            meta = mkOption {
              description = "Information about the contract type and its maintenance.";
              type = types.submodule {
                options = {
                  description = mkOption {
                    description = "What the contract type is for.";
                    type = types.str;
                  };
                  maintainers = mkOption {
                    description = "Maintainers of the contract type.";
                    type = types.listOf types.attrs;
                  };
                };
              };
            };
            interface = mkOption {
              description = "Module with the options `request` and `response`.";
              type = types.deferredModule;
            };
          };
        }
      );
    };

    contracts = mkOption {
      description = ''
        Contract instances, one attribute set for each contract type
        in [](#opt-contractTypes).

        A consumer sets the `request` of its entries in `contracts.<type>.instances`,
        and reads their `response`.
        A provider adds its name to the types of `contracts.<type>.defaultProvider`
        and `contracts.<type>.instances.<name>.provider`,
        and sets the `response` of each entry with its name in `provider`.
        The user selects a provider with `contracts.<type>.defaultProvider`,
        or for one entry with `contracts.<type>.instances.<name>.provider`.
      '';
      default = { };
      type = types.submodule {
        options = lib.mapAttrs (
          contractName: contractType:
          mkOption {
            description = ''
              Instances of the contract type `${contractName}`.

              ${contractType.meta.description}
            '';
            default = { };
            type = types.submodule (
              { config, ... }:
              {
                options = {
                  instances = mkOption {
                    description = ''
                      Instances of the contract type `${contractName}`.
                      Each name must be unique for all consumers,
                      for example `<consumer>-<option>`.

                      Each entry has the options `request` and `response` of the interface of `${contractName}`.
                      A consumer sets the `request`, and reads the `response`.
                      The provider in `provider` sets the `response`.

                      **Example:**

                      ```nix
                      contracts.${contractName}.instances."<consumer>-<option>".request = { };
                      services."<consumer>"."<option>" = config.contracts.${contractName}.instances."<consumer>-<option>".response;
                      ```
                    '';
                    default = { };
                    type = types.attrsOf (
                      types.submodule {
                        imports = [ contractType.interface ];

                        options.provider = mkOption {
                          description = ''
                            The name of the provider that gets the `request` and sets the `response`.
                            To connect this entry to a provider manually, set it to `null`,
                            and set the `response`.
                          '';
                          # Each provider adds its name.
                          type = types.nullOr (types.enum [ ]);
                          default = config.defaultProvider;
                          defaultText = lib.literalExpression "config.contracts.${contractName}.defaultProvider";
                        };

                        options.providerOptions = mkOption {
                          description = ''
                            Options of the providers for this entry, that are not part of the contract.
                            Each provider adds an attribute set of options with its name.
                          '';
                          default = { };
                          type = types.submodule { };
                        };
                      }
                    );
                  };

                  defaultProvider = mkOption {
                    description = ''
                      The name of the provider that gets the requests.
                      To send an entry to a different provider, set `instances.<name>.provider`.
                    '';
                    default = null;
                    # Each provider adds its name.
                    type = types.nullOr (types.enum [ ]);
                    example = "hardcoded-secret";
                  };
                };
              }
            );
          }
        ) config.contractTypes;
      };
    };
  };
}
