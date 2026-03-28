{ lib, ... }:
{
  /**
    Generate contract requests for a service.

    This creates the `contractRequests` configuration for a service module,
    automatically registering all contract options.

    ```nix
    contractRequests = lib.contract.mkRequests "myService" contractOptions config;
    ```

    # Inputs

    `serviceName`

    : 1\. Name of the service (e.g., `"ghostunnel"`)

    `contractOptions`

    : 2\. Attribute set mapping contract types to option names, e.g., `{ fileSecrets = [ "secret1" "secret2" ]; }`

    `serviceConfig`

    : 3\. The service's config attribute set (usually `config`)

    # Type

    ```
    lib.contract.mkRequests :: String -> AttrsOf (ListOf String) -> Attrs -> AttrsOf (AttrsOf (AttrsOf Attrs))
    ```
  */
  mkRequests = serviceName: contractOptions: serviceConfig:
    lib.mapAttrs (
      _: optionNames:
        { ${serviceName} = lib.genAttrs optionNames (name: serviceConfig.${serviceName}.${name}); }
    ) contractOptions;

  /**
    Generate contract output injections for a service.

    This creates configuration that automatically injects fulfilled contract
    outputs into the service's options.

    ```nix
    myService = { }
      // lib.contract.mkOutputs "myService" contractOptions contracts;
    ```

    # Inputs

    `serviceName`

    : 1\. Name of the service (e.g., `"ghostunnel"`)

    `contractOptions`

    : 2\. Attribute set mapping contract types to option names, e.g., `{ fileSecrets = [ "secret1" "secret2" ]; }`

    `contracts`

    : 3\. The contracts attribute set (from specialArgs)

    # Type

    ```
    lib.contract.mkOutputs :: String -> AttrsOf (ListOf String) -> Attrs -> Attrs
    ```
  */
  mkOutputs = serviceName: contractOptions: contracts:
    lib.mkMerge (
      lib.mapAttrsToList (
        contractType: optionNames:
          lib.genAttrs optionNames (
            name: {
              output = lib.attrByPath
                [ contractType "instances" serviceName name "output" ]
                { }
                contracts;
            }
          )
      ) contractOptions
    );
}
