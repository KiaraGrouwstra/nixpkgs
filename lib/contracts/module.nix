{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    nestedAttrsOf
    submodule
    ;
in
{
  options = {
    contractDefinitions = mkOption {
      description = ''
        Registry of contract types available in this module evaluation.

        Each entry declares a contract's `meta` (description,
        maintainers) and `interface.{request,result}` schemas, which
        are used to synthesise the `contracts.<name>` options.

        Adding a new contract type at the call site:

        ```nix
        contractDefinitions.myContract = {
          meta = { description = "..."; maintainers = [ ]; };
          interface = {
            request.someInput = lib.mkOption { type = lib.types.str; };
            result.someOutput = lib.mkOption { type = lib.types.str; };
          };
        };
        ```
      '';
      type = attrsOf lib.contract.definitionType;
      default = { };
    };
    contracts = mkOption {
      description = ''
        Contract instances, keyed by contract type registered in
        `contractDefinitions`.

        Consumers set `contracts.<type>.want.<field> = ...`.
        Fulfillers set `contracts.<type>.result.<field> = ...`.
      '';
      default = { };
      type = submodule {
        options = lib.mapAttrs (
          contractName: contractType:
          let
            inherit (contractType) meta interface;
            requestLeafType = submodule { options = interface.request; };
            resultLeafType = submodule { options = interface.result; };
          in
          mkOption {
            description = meta.description;
            default = { };
            type = submodule {
              options = {
                want = mkOption {
                  description = ''
                    Requests declared by consumers of the `${contractName}` contract.

                    `want` uses `nestedAttrsOf`, so entries may be organized at any depth:

                    ```nix
                    contracts.${contractName}.want."<consumer>" = {
                      flat.someField = ...;
                      grouped.primary.someField = ...;
                      deeply.nested.entry.someField = ...;
                    };
                    ```
                  '';
                  type = nestedAttrsOf requestLeafType;
                  default = { };
                };
                result = mkOption {
                  description = ''
                    Fulfilled results for the `${contractName}` contract, mirroring the
                    structure of `want`.

                    Fulfillers populate `result.<path>.<field>`; consumers read it back
                    via `config.contracts.${contractName}.result.<path>.<field>`.
                  '';
                  type = nestedAttrsOf resultLeafType;
                  default = { };
                };
              };
            };
          }
        ) config.contractDefinitions;
      };
    };
  };
}
