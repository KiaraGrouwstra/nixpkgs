{
  lib,
  ...
}:
{
  meta.maintainers = [ lib.maintainers.kiara ];

  name = "contracts_filesecrets_hardcoded-secret-want";

  # Exercises the code path where the provider config sets only `content`
  # (no `request` block), so the fix must pull owner/group from
  # `config.contracts.fileSecrets.requests` rather than from the provider
  # submodule defaults which fall back to root:root.
  nodes.machine =
    { config, ... }:
    {
      imports = [
        ../../../modules/testing/hardcoded-secret.nix
      ];

      contracts.fileSecrets.want.consumer.thesecret.request = {
        owner = "alice";
        group = "alice";
        mode = "0400";
      };
      contracts.fileSecrets.defaultProvider = config.contracts.fileSecrets.providers.hardcoded-secret;

      testing.hardcoded-secret.fileSecrets.consumer.thesecret.content = "topsecret";

      users.users.alice.isNormalUser = true;
      users.groups.alice = { };
    };

  testScript =
    { nodes, ... }:
    let
      result = nodes.machine.contracts.fileSecrets.results.consumer.thesecret;
    in
    ''
      owner = machine.succeed("stat -c '%U' ${result.path}").strip()
      print(f"Got owner {owner}")
      if owner != "alice":
          raise Exception(f"Owner should be 'alice' but got '{owner}'")

      group = machine.succeed("stat -c '%G' ${result.path}").strip()
      print(f"Got group {group}")
      if group != "alice":
          raise Exception(f"Group should be 'alice' but got '{group}'")

      mode = str(int(machine.succeed("stat -c '%a' ${result.path}").strip()))
      print(f"Got mode {mode}")
      if mode != "400":
          raise Exception(f"Mode should be '400' but got '{mode}'")

      content = machine.succeed("cat ${result.path}").strip()
      print(f"Got content {content}")
      if content != "topsecret":
          raise Exception(f"Content should be 'topsecret' but got '{content}'")
    '';
}
