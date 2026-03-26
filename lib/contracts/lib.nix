{ lib, ... }:
{
  /**
    Get the request inputs for a given contract.
    A provider may use this to assign to its contract instances:

    ```nix
    services.<provider>.<contract> = lib.contract.getInputs config.contracts.<contract>;
    ```

    Filtering request content this way helps prevent an infinite recursion through `output`s.

    # Inputs

    `contract`

    : 1\. the contract for which to get request inputs

    # Type

    ```
    lib.contract.getInputs :: Contract -> attrsOf (attrsOf attrs)
    ```
  */
  getInputs = contract: lib.mapAttrs (
    _: lib.mapAttrs (_: lib.getAttrs [ "input" ])
  ) contract.requests;
}
