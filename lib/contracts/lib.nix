{ lib, ... }:
{
  /**
    Get the request inputs for a given contract.

    # Inputs

    `contract`

    : 1\. the contract for which to get request inputs

    # Type

    ```
    getInputs :: Contract -> attrsOf (attrsOf attrs)
    ```
  */
  getInputs = contract: lib.mapAttrs (
    _: lib.mapAttrs (_: instance: { inherit (instance) input; })
  ) contract.requests;
}
