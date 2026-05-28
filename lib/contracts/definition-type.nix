{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    attrsOf
    listOf
    optionDeclaration
    str
    submodule
    ;
in
submodule {
  options = {
    meta = mkOption {
      description = ''
        Useful information about the contract and its maintenance.
      '';
      type = submodule {
        options = {
          description = mkOption {
            description = "Description of the contract.";
            type = str;
          };
          maintainers = mkOption {
            description = "Maintainers of the contract.";
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
      type = submodule {
        options = {
          request = mkOption {
            description = "Request type of the contract.";
            type = attrsOf optionDeclaration;
            default = { };
          };
          result = mkOption {
            description = "Result type of the contract.";
            type = attrsOf optionDeclaration;
            default = { };
          };
        };
      };
    };
  };
}
