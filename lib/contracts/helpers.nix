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
    Rebind every contract's `mkProviderType` against a NixOS module's `config`,
    returning an attrset shaped like `lib.contracts`.

    For each contract, prefers the bridge (`config.contracts.<name>.mkProviderType`)
    when available - the bridge pre-binds `_requests` so consumer `want` request
    data is forwarded into each leaf (see `mkProviderType`'s `_requests`
    parameter in `./definition-type.nix`). Falls back to the pure lib function
    when `config.contracts` is absent (e.g. inside the manual docs build's
    per-module sandbox, where the contracts module is not imported); the lib
    version produces an identical option type shape, only without runtime want
    forwarding, which is irrelevant to rendered docs.

    Use this in provider modules to bind one or more contracts at once:

    ```nix
    inherit (lib.contract.forModule config) fileSecrets arithmetic;
    # then: type = fileSecrets.mkProviderType { ... };
    #       type = arithmetic.mkProviderType { ... };
    ```

    lib.contract.forModule :: moduleConfig -> { <contractName> = contract; ... }
  */
  forModule =
    moduleConfig:
    lib.mapAttrs (
      name: contract:
      contract
      // {
        mkProviderType = moduleConfig.contracts.${name}.mkProviderType or contract.mkProviderType;
      }
    ) lib.contracts;
}
