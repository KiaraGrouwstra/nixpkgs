{ lib, ... }:
{
  /**
    Whether a value is a contract instance (an attrset with `request` and `result`).

    Useful when an option accepts both a contract type and a plain value
    (e.g. `types.oneOf [ types.path contractType ]` or `types.nullOr contractType`)
    and the consumer needs to branch on which was provided.

    lib.contract.isInstance :: a -> bool

    # Example

    ```nix
    if lib.contract.isInstance cfg.passwordFile
    then cfg.passwordFile.result.path
    else cfg.passwordFile
    ```
  */
  isInstance = v: lib.isAttrs v && v ? result;

  /**
    Read the canonical request for a provider entry.

    Prefers the want-derived `requests` view (authoritative when a consumer
    has declared the entry via `contracts.<type>.want.<consumer>.<...>`),
    falls back to the entry's own `request` (for entries set directly on
    the provider option, e.g. via the `behaviorTest` framework).

    lib.contract.readRequest :: AttrSet -> [ String ] -> { request, ... } -> AttrSet

    # Example

    ```nix
    (lib.concatMapNestedAttrs' cfg.fileSecrets.type
      (path: cfg':
        let
          request = lib.contract.readRequest
            config.contracts.fileSecrets.requests path cfg';
        in { /* use request.owner, request.group, ... */ })
      cfg.fileSecrets)
    ```
  */
  readRequest =
    requests: path: cfg':
    let
      r = lib.attrByPath path null requests;
    in
    if r != null then r.request else cfg'.request;
}
