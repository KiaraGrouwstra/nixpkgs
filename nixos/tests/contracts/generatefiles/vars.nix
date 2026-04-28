# Tests the vars + vars-on-machine providers end-to-end.
#
# Exercises the generateFiles contract with the on-machine varsBackend,
# and verifies that generated files are also accessible through the
# fileSecrets contract bridge.
{ lib, pkgs, ... }:
let
  secretOwner = "testuser";
  secretGroup = "testgroup";
  secretMode = "0440";
in
{
  name = "contracts-generatefiles-vars";

  containers.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../../../modules/services/security/vars.nix
        ../../../modules/services/security/vars-on-machine.nix
      ];

      contracts.generateFiles.defaultProviderName = "vars";
      contracts.varsBackend.defaultProviderName = "on-machine";
      contracts.fileSecrets.defaultProviderName = "vars";

      # The always-loaded hardcoded-secret module's `default` propagates every
      # fileSecrets request into its option, then iterates assuming each entry
      # has a `content` providerOption. Force it empty when not the chosen
      # provider so it doesn't error on the bridge entries.
      testing.hardcoded-secret.fileSecrets = lib.mkForce { };

      contracts.generateFiles.want.myapp = {
        request = {
          files = {
            fileA = {
              owner = secretOwner;
              group = secretGroup;
              mode = secretMode;
            };
            fileB = {
              owner = secretOwner;
              group = secretGroup;
              mode = secretMode;
            };
          };
          runtimeInputs = [ pkgs.coreutils ];
          script = ''
            echo -n "generated-secret-A" > "$out"/fileA
            echo -n "generated-secret-B" > "$out"/fileB
          '';
        };
      };

      users.users.${secretOwner} = {
        isNormalUser = true;
        group = secretGroup;
      };
      users.groups.${secretGroup} = { };
    };

  testScript =
    { containers, ... }:
    let
      gfResults = containers.machine.contracts.generateFiles.results.myapp.files;
      pathA = gfResults.fileA.path;
      pathB = gfResults.fileB.path;

      # fileSecrets bridge paths should resolve identically
      fsResults = containers.machine.contracts.fileSecrets.results.vars;
      fsPathA = fsResults.myapp_fileA.path;
      fsPathB = fsResults.myapp_fileB.path;
    in
    assert fsPathA == pathA;
    assert fsPathB == pathB;
    ''
      machine.wait_for_unit("generate-vars.service")
      machine.wait_for_file("${pathA}")
      machine.wait_for_file("${pathB}")

      for file_name, path, expected_content in [
          ("fileA", "${pathA}", "generated-secret-A"),
          ("fileB", "${pathB}", "generated-secret-B"),
      ]:
          content = machine.succeed(f"cat {path}").strip()
          assert content == expected_content, \
              f"{file_name}: expected '{expected_content}', got '{content}'"

          owner = machine.succeed(f"stat -c '%U' {path}").strip()
          assert owner == "${secretOwner}", \
              f"{file_name}: expected owner '${secretOwner}', got '{owner}'"

          group = machine.succeed(f"stat -c '%G' {path}").strip()
          assert group == "${secretGroup}", \
              f"{file_name}: expected group '${secretGroup}', got '{group}'"

          mode = str(int(machine.succeed(f"stat -c '%a' {path}").strip()))
          expected_mode = str(int("${secretMode}"))
          assert mode == expected_mode, \
              f"{file_name}: expected mode '{expected_mode}', got '{mode}'"

      # Verify fileSecrets bridge: same files accessible through fileSecrets contract paths
      fs_content_a = machine.succeed("cat ${fsPathA}").strip()
      assert fs_content_a == "generated-secret-A", \
          f"fileSecrets fileA: expected 'generated-secret-A', got '{fs_content_a}'"

      fs_content_b = machine.succeed("cat ${fsPathB}").strip()
      assert fs_content_b == "generated-secret-B", \
          f"fileSecrets fileB: expected 'generated-secret-B', got '{fs_content_b}'"
    '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
