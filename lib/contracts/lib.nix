{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    functionTo
    listOf
    option
    optionType
    raw
    str
    submodule
    ;
in
let
  /**
    Evaluate a configuration in the context of a corresponding module system option.

    contract.evalOption :: option -> attrs -> attrs

    # Inputs

    `option`

    : 1\. Module system option in which to evaluate the configuration

    `conf`

    : 2\. Configuration to evaluate within the option
  */
  evalOption =
    option: conf:
    (lib.evalModules {
      modules = [
        {
          options.opt = option;
          config.opt = conf;
        }
      ];
    }).config.opt;

  /**
    Extend a (sub-)module option with a set of overrides.

    contract.extendOption :: attrs -> option -> option

    # Inputs

    `overrides`

    : 1\. A (recursive) attrset of fields to add to the option

    `opt`

    : 2\. Option to extend with `overrides`

    Example:

    ```nix
    { config, lib, ... }:
    let
      inherit (lib) mkOption contract types;
    in
    {
      options.foo = contract.extendOption
        {
          bar = {
            default = 10;
            defaultText = "10";
          };
        }
        (mkOption {
          type = types.submodule {
            options.bar = mkOption {
              type = types.int;
            };
          };
        })
    }
    ```
  */
  extendOption =
    overrides: opt:
    let
      inherit (opt) type;
      isSubmodule = lib.isOptionType type && type.name == "submodule";
      # (deduplicated) keys from submodules to iterate over
      # we don't need the values, but attrset offers O(1) containment checks
      subOptions = lib.optionalAttrs isSubmodule (
        lib.attrsets.mergeAttrsList (lib.lists.map (mod: mod.options or { }) type.getSubModules)
      );
      subOverrides = lib.filterAttrs (k: _: subOptions ? ${k}) overrides;
      directOverrides = lib.filterAttrs (k: _: !(subOptions ? ${k})) overrides;
    in
    mkOption (
      # re-wrap existing option attributes
      (removeAttrs opt [ "_type" ])
      # if we are annotating something that isn't a sub-module,
      # just override relevant attributes on the option
      // directOverrides
      # to annotate a sub-module, presume we should just annotate its sub-options,
      # which we iterate over to reconstruct with relevant annotations.
      // lib.optionalAttrs isSubmodule {
        default = { };
        type = lib.types.submoduleWith (
          # meta we will not change
          type.functor.payload
          # modules are the parameter that will change as per our overrides
          // {
            modules = [
              {
                options = lib.mapAttrs (
                  k: _:
                  let
                    # option for the attribute in question: for now presume just one sub-module had it
                    attrOpt = (lib.head (lib.filter (m: (m.options or { }) ? ${k}) type.getSubModules)).options.${k};
                    # any overrides for the attribute in question
                    attrOverrides = subOverrides.${k} or { };
                  in
                  # recurse until we have no more overrides to annotate the option with
                  if attrOverrides != { } then extendOption attrOverrides attrOpt else attrOpt
                ) subOptions;
              }
            ];
          }
        );
      }
    );

  /**
    Extend a (sub-)module type with a set of overrides.

    contract.extendSubmodule :: attrs -> optionType -> optionType

    # Inputs

    `overrides`

    : 1\. A (recursive) attrset of fields to add to the option

    `mod`

    : 2\. A (sub-)module type to extend with `overrides`

    Example:

    ```nix
    { config, lib, ... }:
    let
      inherit (lib) mkOption contract types;
    in
    {
      options.foo = mkOption {
        default = { };
        type = contract.extendSubmodule
          bar = {
            default = 10;
            defaultText = "10";
          };
          (types.submodule {
            options.bar = mkOption {
              type = types.int;
            };
          });
      };
    }
    ```
  */
  extendSubmodule =
    overrides: mod:
    (extendOption overrides (mkOption {
      default = { };
      type = mod;
    })).type;

  templateType = submodule (contract: {
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
              extraImports = mkOption {
                description = "Extra imports for the request and result submodules (e.g. rename shims).";
                default = { };
                type = submodule {
                  options = lib.genAttrs [ "request" "result" ] (k: mkOption {
                    description = "Extra imports for the ${k} submodule.";
                    type = listOf raw;
                    default = [ ];
                  });
                };
              };
            };
          };
      };
      mkContract = mkOption {
        description = ''
          Augment the contract interface's type using a set of overrides.

          `contract.mkContract :: attrs -> optionType`

          **Inputs:**

          `overrides`

          : 1\. A (recursive) attrset of fields to add to the contract interface submodule type

          **Example:**

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
                };
            };
          }
          ```
        '';
        type = functionTo optionType;
        readOnly = true;
        default =
          overrides:
          let
            inherit (contract.config) interface;
          in
          lib.extendSubmodule overrides (submodule {
            options = lib.mapAttrs (
              k: options:
              mkOption {
                description = "The ${k} of the contract instance.";
                type = submodule {
                  imports = interface.extraImports.${k};
                  inherit options;
                };
              }
            ) (lib.getAttrs [ "request" "result" ] interface);
          });
      };
      extend = mkOption {
        description = ''
          Construct a type for a provider's individual request or result option, with overrides applied.

          `extend.request overrides` and `extend.result overrides` produce types for the respective interface parts.
        '';
        type = attrsOf (functionTo optionType);
        readOnly = true;
        default =
          let
            inherit (contract.config) interface;
          in
          lib.mapAttrs (
            k: options: overrides:
            lib.extendSubmodule overrides (
              lib.types.submodule {
                imports = interface.extraImports.${k};
                inherit options;
              }
            )
          ) (lib.getAttrs [ "request" "result" ] interface);

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
  });
in
{
  inherit
    evalOption
    extendOption
    extendSubmodule
    templateType
    ;
}
