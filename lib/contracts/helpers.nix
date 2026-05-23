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
    Generic skeleton for a contract `behaviorTest`.

    Abstracts the contract-name prefix, want-path wiring, and result extraction,
    leaving only per-contract pieces (test options, request shape, nodeConfig,
    testScript body) to the caller.

    lib.contract.mkBehaviorTest :: { contractName, testName, wantPath, ... } -> NixOSTest

    # Arguments

    - `contractName`: attrset key under `config.contracts` (e.g. `"fileSecrets"`)
    - `testName`: test-name suffix; produces `contracts_<contractName>_<testName>`
    - `wantPath`: attr-path list into `contracts.<contractName>.want`
    - `extraModules`: extra NixOS modules for the test machine (optional, default `[]`)
    - `nodeModule`: NixOS module that defines per-contract `options` and their config
      (e.g. `options.test.*`, user/group autocreation)
    - `requestOf`: `config -> request` — derive the contract request attrset from
      the evaluated node config
    - `testScript`: `{ result, nodes } -> string` — return the Python test script;
      `result` is the already-resolved result attrset for `wantPath`
  */
  mkBehaviorTest =
    {
      contractName,
      testName,
      wantPath,
      extraModules ? [ ],
      nodeModule,
      requestOf,
      testScript,
    }:
    {
      name = "contracts_${contractName}_${testName}";
      nodes.machine =
        { config, ... }:
        {
          imports = extraModules ++ [ nodeModule ];
          config = lib.setAttrByPath
            ([ "contracts" contractName "want" ] ++ wantPath ++ [ "request" ])
            (requestOf config);
        };
      testScript =
        { nodes, ... }:
        testScript {
          result = lib.getAttrFromPath ([ "contracts" contractName "results" ] ++ wantPath) nodes.machine;
          inherit nodes;
        };
    };
}
