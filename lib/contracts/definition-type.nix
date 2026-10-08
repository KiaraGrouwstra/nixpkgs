# Module of a contract type: the options of each entry in `contractTypes`.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  # Module that imports `interface`, and adds the attributes in `overrides` to its options.
  # The empty definitions let the user omit an option of the interface,
  # if each of its options has a default.
  interfaceWith = overrides: {
    imports = [ config.interface ];
    options = lib.mapAttrs (
      _: options:
      mkOption {
        type = types.submodule { options = lib.mapAttrs (_: mkOption) options; };
      }
    ) overrides;
    config = lib.mapAttrs (_: _: { }) overrides;
  };
in
{
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

    mkContract = mkOption {
      description = ''
        Make a submodule type that imports `interface`,
        and add the attributes in `overrides` to its options.

        `mkContract :: attrs -> optionType`

        **Inputs:**

        `overrides`

        : 1\. For each option of the interface, such as `request`,
          an attribute set with the attributes to add to each of its options,
          such as `default` or `readOnly`.

        **Example:**

        ```nix
        lib.contracts.fileSecrets.mkContract {
          request.owner = {
            default = cfg.user;
            readOnly = true;
          };
        }
        ```

        The result is the same type as:

        ```nix
        types.submodule {
          imports = [ lib.contracts.fileSecrets.interface ];
          options.request = mkOption {
            type = types.submodule {
              options.owner = mkOption {
                default = cfg.user;
                readOnly = true;
              };
            };
          };
          config.request = { };
        }
        ```

        The empty definition `config.request = { }` lets the user omit `request`,
        if each option of `request` has a default.
      '';
      type = types.functionTo types.optionType;
      readOnly = true;
      default = overrides: types.submodule (interfaceWith overrides);
      defaultText = lib.literalMD "a function that makes a submodule type from `interface` and `overrides`";
    };

    mkProviderType = mkOption {
      description = ''
        Make the type of the option in which a provider gets its requests.
        The type is `nestedAttrsOf` a submodule that imports `interface`.

        `mkProviderType :: { overrides?, providerOptions?, fulfill?, fulfill'? } -> optionType`

        **Inputs:**

        `overrides`

        : 1\. Attributes to add to the options of the interface, as in `mkContract`.

        `providerOptions`

        : 2\. Options of the provider that are not part of the contract type.
          They are in the option `providerOptions` of each entry.

        `fulfill`

        : 3\. Function from the `request` of an entry to its `response`.
          Each attribute of the result has `mkDefault` priority,
          thus a definition of the same `response` option replaces it.

        `fulfill'`

        : 4\. Function from `{ request, name, loc, instance }` to the `response` of an entry.
          `name` is the last attribute name of the entry,
          `loc` is the location of the entry,
          and `instance` is the configuration of the entry.
          Set `fulfill` or `fulfill'`, not the two.

        **Example:**

        ```nix
        { config, ... }:
        {
          options.services.increment.numbers = lib.mkOption {
            type = config.contractTypes.number.mkProviderType {
              fulfill = request: { value = request.value + 1; };
            };
          };
          config = {
            services.increment.numbers = config.contracts.number.providerRequests.increment;
            contracts.number.providers.increment = config.services.increment.numbers;
          };
        }
        ```
      '';
      type = types.functionTo types.optionType;
      readOnly = true;
      default =
        {
          overrides ? { },
          providerOptions ? { },
          fulfill ? null,
          fulfill' ? null,
        }:
        assert lib.assertMsg (
          fulfill == null || fulfill' == null
        ) "mkProviderType: set `fulfill` or `fulfill'`, not the two.";
        let
          fulfill'' = if fulfill != null then { request, ... }: fulfill request else fulfill';
        in
        types.nestedAttrsOf (
          types.submodule (
            {
              config,
              options,
              name,
              ...
            }:
            {
              imports = [ (interfaceWith overrides) ];
              options.providerOptions = mkOption {
                description = "Options of the provider that are not part of the contract type.";
                default = { };
                type = types.submodule { options = providerOptions; };
              };
              config.response = lib.mkIf (fulfill'' != null) (
                lib.mapAttrs (_: lib.mkDefault) (fulfill'' {
                  inherit (config) request;
                  inherit name;
                  loc = lib.init options.request.loc;
                  instance = config;
                })
              );
            }
          )
        );
      defaultText = lib.literalMD "a function that makes a `nestedAttrsOf` type from `interface` and the inputs";
    };
  };
}
