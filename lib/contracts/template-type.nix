{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    functionTo
    listOf
    optionDeclaration
    str
    submodule
    ;
in
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
          type = attrsOf optionDeclaration;
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
      defaultText = lib.literalExpression ''
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
