# Functions to use contracts.
# The contract types of NixOS are in `nixos/modules/contracts`.
{ lib, ... }:
let
  inherit (lib)
    all
    concatMapStrings
    filterAttrs
    head
    isAttrs
    literalExpression
    literalMD
    mkOption
    showOption
    types
    ;
in
{
  /**
    Make the option of a contract type, with the options `instances`, `providers` and `defaultProvider`.

    Declare it at `options.contracts.<name>` in a module.
    Each entry of `instances` imports `interface`, thus it has the options `request` and `response`.

    A provider adds an entry with its name to `providers`.
    A provider can also declare options in `instances` through option declaration merging:
    its options for one entry in `instances.<name>.providerOptions.<provider>`,
    and a `config.response` for the entries in `providers.<provider>.instances`.

    # Type

    ```
    mkContractOption :: { name :: string; description :: string; interface :: module; } -> option
    ```

    # Inputs

    `name`

    : The name of the contract type, that is the name of the option in `contracts`.

    `description`

    : What the contract type is for.

    `interface`

    : A module with the options `request` and `response`.

    # Example

    ```nix
    {
      options.contracts.number = mkContractOption {
        name = "number";
        description = "A number.";
        interface.options = {
          request = mkOption { type = types.int; };
          response = mkOption { type = types.int; };
        };
      };
    }
    ```
  */
  mkContractOption =
    {
      name,
      description,
      interface,
    }:
    let
      contractName = name;

      # An entry of `providers`. A string is not a provider, thus a typo is an error.
      providerType = types.mkOptionType {
        name = "contractProvider";
        description = "provider of the contract type `${contractName}`";
        descriptionClass = "noun";
        check = v: isAttrs v && v.contract or null == contractName && v ? name;
        # A provider has functions in `_module`, thus compare the names.
        merge =
          loc: defs:
          let
            first = head defs;
          in
          if all (def: def.value.name == first.value.name) defs then
            first.value
          else
            throw "The option `${showOption loc}' has conflicting providers:${
              concatMapStrings (def: "\n- In `${def.file}': `${def.value.name}'") defs
            }";
      };
    in
    mkOption {
      description = ''
        The contract type `${contractName}`: ${description}

        A consumer sets the `request` of its entries in `instances`, and reads their `response`.
        The provider in `provider` sets the `response`.
      '';
      default = { };
      type = types.submodule (
        { config, ... }:
        {
          options = {
            instances = mkOption {
              description = ''
                Instances of the contract type `${contractName}`.
                Each name must be unique for all consumers, for example `<consumer>-<option>`.

                Each entry has the options `request` and `response` of the contract type.
                A consumer sets the `request`, and reads the `response`.
                The provider in `provider` sets the `response`.
              '';
              default = { };
              type = types.attrsOf (
                types.submodule {
                  imports = [ interface ];

                  options.provider = mkOption {
                    description = ''
                      The provider that gets the `request` and sets the `response`, an entry of `providers`.
                      To connect this entry to a provider manually, set it to `null`, and set the `response`.
                    '';
                    type = types.nullOr providerType;
                    default = config.defaultProvider;
                    defaultText = literalExpression "config.contracts.${contractName}.defaultProvider";
                  };

                  options.providerOptions = mkOption {
                    description = ''
                      Options of the providers for this entry, that are not part of the contract.
                      Each provider adds a set of options with its name.
                    '';
                    default = { };
                    type = types.submodule { };
                  };
                }
              );
            };

            providers = mkOption {
              description = ''
                Providers of the contract type `${contractName}`.
                Each provider adds an entry with its name.
                Use an entry as the value of `defaultProvider` or `instances.<name>.provider`.
              '';
              default = { };
              type = types.attrsOf (
                types.submodule (
                  { name, ... }:
                  {
                    options = {
                      name = mkOption {
                        description = "The name of the provider.";
                        type = types.str;
                        default = name;
                        defaultText = literalExpression ''"<name>"'';
                        readOnly = true;
                      };

                      contract = mkOption {
                        description = "The name of the contract type of the provider.";
                        type = types.str;
                        default = contractName;
                        readOnly = true;
                      };

                      instances = mkOption {
                        description = "The entries of `instances` with this provider in `provider`.";
                        type = types.lazyAttrsOf types.raw;
                        default = filterAttrs (
                          _: instance: instance.provider != null && instance.provider.name == name
                        ) config.instances;
                        defaultText = literalMD "the entries of `instances` with this provider in `provider`";
                        readOnly = true;
                      };
                    };
                  }
                )
              );
            };

            defaultProvider = mkOption {
              description = ''
                The provider that gets the requests, an entry of `providers`.
                To send an entry to a different provider, set `instances.<name>.provider`.
              '';
              type = types.nullOr providerType;
              default = null;
              example = literalExpression "config.contracts.${contractName}.providers.<provider>";
            };
          };
        }
      );
    };

  /**
    Whether a value is a contract, that is an attribute set with a `response`.

    Use it when an option accepts a contract or a value without a contract,
    for example `types.oneOf [ types.path contractType ]`,
    to find which of the two the user set.

    # Type

    ```
    isInstance :: a -> bool
    ```

    # Inputs

    `v`

    : 1\. The value to test

    # Example

    ```nix
    isInstance { response.path = "/run/secrets/a"; }
    # => true
    isInstance /run/secrets/a
    # => false
    ```
  */
  isInstance = v: lib.isAttrs v && v ? response;
}
