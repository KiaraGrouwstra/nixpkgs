{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    nestedAttrsOf
    raw
    submodule
    ;
in
{
  options = {
    contractDefinitions = mkOption {
      description = ''
        Types of contracts. Each entry declares a contract's `meta` (description,
        maintainers) and `interface.{request,result}` schemas.

        Instances of these contracts are configured via `contracts.<name>`.

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

        **Integrating into a new module system** (e.g. home-manager, nix-darwin):

        Import `lib.contract.module` and populate `contractDefinitions` with the
        contract definitions you want to make available.
      '';
      type = attrsOf lib.contract.definitionType;
      default = { };
    };
    contracts = mkOption {
      description = ''
        Contract instances, keyed by contract type.

        Consumers set `contracts.<type>.want.<path>.request.<field> = ...`.
        Fulfillers set `contracts.<type>.want.<path>.result.<field> = ...`.

        Each leaf of the `want` tree carries both the consumer's `request`
        and the fulfiller's `result`, so a single nested-attrs traversal
        sees both sides paired up. Consumers conventionally read fulfilled
        values via the `results` projection.
      '';
      default = { };
      type = submodule {
        options = lib.mapAttrs (
          contractName: contractType:
          let
            inherit (contractType) meta interface;
            leafType = submodule {
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
                    Result populated by the fulfiller of the `${contractName}` contract.
                    Must match the `${contractName}` contract interface's result type.
                  '';
                  type = submodule { options = interface.result; };
                };
              };
            };
          in
          mkOption {
            description = meta.description;
            default = { };
            type = submodule (contract: {
              options = {
                want = mkOption {
                  description = ''
                    Requests and fulfilled results for the `${contractName}` contract.

                    Each leaf carries both `request` (consumer-set) and `result`
                    (fulfiller-set). `nestedAttrsOf` lets entries be organized at any depth:

                    ```nix
                    contracts.${contractName}.want."<consumer>" = {
                      flat = { request = ...; result = ...; };
                      grouped.primary = { request = ...; result = ...; };
                      deeply.nested.entry = { request = ...; result = ...; };
                    };
                    ```

                    **Naming restrictions:** namespace keys must not be literally
                    `request` or `result`, otherwise they would be misidentified
                    as leaves by `nestedAttrsOf`'s leaf-detection heuristic.
                  '';
                  type = nestedAttrsOf leafType;
                  default = { };
                };
                requests = mkOption {
                  description = ''
                    Read-only projection of `want` to just the `request` attributes.

                    Fulfillers consume this to enumerate consumer requests
                    without manually projecting each leaf.
                  '';
                  type = nestedAttrsOf raw;
                  readOnly = true;
                  default = lib.mapNestedAttrs' (nestedAttrsOf leafType) (v: v.request) contract.config.want;
                  defaultText = lib.literalExpression ''
                    lib.mapNestedAttrs' (nestedAttrsOf leafType) (v: v.request) want
                  '';
                };
                results = mkOption {
                  description = ''
                    Read-only projection of `want` to just the `result` attributes.

                    Consumers read the fulfilled value via
                    `config.contracts.${contractName}.results.<path>.<field>`.
                  '';
                  type = nestedAttrsOf raw;
                  readOnly = true;
                  default = lib.mapNestedAttrs' (nestedAttrsOf leafType) (v: v.result) contract.config.want;
                  defaultText = lib.literalExpression ''
                    lib.mapNestedAttrs' (nestedAttrsOf leafType) (v: v.result) want
                  '';
                };
              };
            });
          }
        ) config.contractDefinitions;
      };
    };
  };
}
