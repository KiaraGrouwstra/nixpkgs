{ lib, ... }:
let
  inherit (lib) getAttrFromPath setAttrByPath;
in
{
  name,
  providerRoot,
  content,
  # The request of the provider entry, made from the request of the consumer.
  # A provider of a different contract type can take a different request.
  providerRequest ? request: request,
  extraModules ? [ ],
  extraTestScript ? "",
}:
{
  name = "contracts_credentialsecrets_${name}";

  nodes.machine =
    { config, ... }:
    let
      consumer = config.test.credential;
    in
    {
      imports = extraModules;

      options.test.credential = lib.mkOption {
        type = lib.types.submodule {
          imports = [ lib.contracts.credentialSecrets.interface ];
        };
      };

      config = lib.mkMerge [
        (setAttrByPath providerRoot {
          request = providerRequest consumer.request;
        })
        {
          test.credential = {
            request = {
              unit = "credential-consumer.service";
              id = "secret";
            };
            response = (getAttrFromPath providerRoot config).response;
          };

          # Copies the credential to a file that the test script reads.
          systemd.services.credential-consumer = {
            serviceConfig = {
              Type = "oneshot";
              DynamicUser = true;
              LoadCredential = "${consumer.request.id}:${consumer.response.path}";
              ExecStart = "${lib.getExe' config.systemd.package "systemd-creds"} cat ${consumer.request.id}";
              StandardOutput = "file:/run/credential-consumer-content";
            };
          };
        }
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl start credential-consumer.service")
    got = machine.succeed("cat /run/credential-consumer-content")
    print(f"Got content {got!r}")
    if got != ${builtins.toJSON content}:
        raise Exception(f"Content should be {${builtins.toJSON content}!r} but got {got!r}")
  ''
  + extraTestScript;
}
