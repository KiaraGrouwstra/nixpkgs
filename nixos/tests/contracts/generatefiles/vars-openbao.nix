# Tests the vars + vars-openbao providers end-to-end.
#
# Full pipeline:
# 1. Consumer provides a generation script via the generateFiles contract
# 2. generate-vars runs the script at boot, writing files locally
# 3. upload-vars-openbao uploads them to OpenBao and removes local copies
# 4. vault-agent fetches them back from OpenBao
# 5. Content, ownership, and permissions are verified
{ lib, pkgs, ... }:
let
  secretOwner = "testuser";
  secretGroup = "testgroup";
  secretMode = "0440";
in
{
  name = "contracts-generatefiles-vars-openbao";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../../../modules/services/security/vars.nix
        ../../../modules/services/security/vars-on-machine.nix
        ../../../modules/services/security/vars-openbao.nix
      ];

      # OpenBao dev server
      systemd.services.openbao-dev = {
        description = "OpenBao Dev Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          BAO_DEV_ROOT_TOKEN_ID = "root";
          BAO_DEV_LISTEN_ADDRESS = "127.0.0.1:8200";
          HOME = "/tmp";
        };
        path = [
          pkgs.bash
          pkgs.coreutils
        ];
        serviceConfig = {
          ExecStart = "${pkgs.openbao}/bin/bao server -dev";
          Restart = "on-failure";
          LimitMEMLOCK = "infinity";
        };
      };

      # vault-agent auth config
      services.vault-agent.instances.vars-openbao = {
        package = pkgs.openbao;
        settings.auto_auth = [
          {
            method = [
              {
                type = "token_file";
                config.token_file_path = pkgs.writeText "vault-token" "root";
              }
            ];
          }
        ];
      };

      # Order services: openbao-dev -> generate-vars -> upload -> vault-agent
      systemd.services.generate-vars.after = [ "openbao-dev.service" ];
      systemd.services.vault-agent-vars-openbao.after = [ "openbao-dev.service" ];

      contracts.generateFiles.defaultProviderName = "vars";
      contracts.varsBackend.defaultProviderName = "openbao";
      contracts.fileSecrets.defaultProviderName = "vars";

      services.vars-openbao.tokenFile = builtins.toFile "vault-token" "root";

      # The always-loaded hardcoded-secret module's `default` propagates every
      # fileSecrets request into its option, then iterates assuming each entry
      # has a `content` providerOption. Force it empty when not the chosen
      # provider so it doesn't error on the bridge entries.
      testing.hardcoded-secret.fileSecrets = lib.mkForce { };

      contracts.generateFiles.want.myapp = {
        request = {
          files = {
            alpha = {
              owner = secretOwner;
              group = secretGroup;
              mode = secretMode;
            };
            beta = {
              owner = secretOwner;
              group = secretGroup;
              mode = secretMode;
            };
          };
          runtimeInputs = [ pkgs.coreutils ];
          script = ''
            echo -n "generated-alpha-secret" > "$out"/alpha
            echo -n "generated-beta-secret" > "$out"/beta
          '';
        };
      };

      users.users.${secretOwner} = {
        isNormalUser = true;
        group = secretGroup;
      };
      users.groups.${secretGroup} = { };

      environment.systemPackages = [ pkgs.openbao ];
    };

  testScript =
    { nodes, ... }:
    let
      results = nodes.machine.contracts.generateFiles.results.myapp.files;
      pathA = results.alpha.path;
      pathB = results.beta.path;

      # fileSecrets bridge: verify paths resolve identically at eval time
      fsResults = nodes.machine.contracts.fileSecrets.results.vars;
      fsPathA = fsResults.myapp_alpha.path;
      fsPathB = fsResults.myapp_beta.path;
    in
    assert fsPathA == pathA;
    assert fsPathB == pathB;
    ''
      machine.wait_for_unit("openbao-dev.service")
      machine.wait_for_open_port(8200)

      # Wait for the full pipeline: generate -> upload -> vault-agent fetch.
      machine.wait_for_unit("generate-vars.service")
      machine.wait_for_unit("upload-vars-openbao.service")
      machine.wait_for_unit("vault-agent-vars-openbao.service")
      machine.wait_for_file("${pathA}")
      machine.wait_for_file("${pathB}")

      # Verify the OpenBao round-trip: the upload service must have written
      # the files under the same path the vault-agent template reads from.
      # With the leaf-name fix, listing `vars/secret/` yields `myapp/`
      # (joined-path bug would yield `vars_myapp/` or nothing).
      kv_listing = machine.succeed(
          "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root "
          "bao kv list -mount=secret vars/secret/"
      )
      assert "myapp/" in kv_listing, \
          f"expected `myapp/` under vars/secret/ in OpenBao, got: {kv_listing!r}"

      myapp_listing = machine.succeed(
          "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root "
          "bao kv list -mount=secret vars/secret/myapp/"
      )
      for f in ("alpha", "beta"):
          assert f in myapp_listing, \
              f"expected `{f}` under vars/secret/myapp/ in OpenBao, got: {myapp_listing!r}"

      # Verify the vault-agent fetch path: delete the local file and wait
      # for vault-agent to re-render it from OpenBao.
      machine.succeed("rm -f ${pathA}")
      machine.wait_for_file("${pathA}")
      content = machine.succeed("cat ${pathA}").strip()
      assert content == "generated-alpha-secret", \
          f"after re-render: expected 'generated-alpha-secret', got '{content}'"

      # Verify file A: content, ownership, permissions
      content = machine.succeed("cat ${pathA}").strip()
      assert content == "generated-alpha-secret", f"alpha: expected 'generated-alpha-secret', got '{content}'"

      owner = machine.succeed("stat -c '%U' ${pathA}").strip()
      assert owner == "${secretOwner}", f"alpha: expected owner '${secretOwner}', got '{owner}'"

      group = machine.succeed("stat -c '%G' ${pathA}").strip()
      assert group == "${secretGroup}", f"alpha: expected group '${secretGroup}', got '{group}'"

      mode = str(int(machine.succeed("stat -c '%a' ${pathA}").strip()))
      expected_mode = str(int("${secretMode}"))
      assert mode == expected_mode, f"alpha: expected mode '{expected_mode}', got '{mode}'"

      # Verify file B
      content = machine.succeed("cat ${pathB}").strip()
      assert content == "generated-beta-secret", f"beta: expected 'generated-beta-secret', got '{content}'"

      owner = machine.succeed("stat -c '%U' ${pathB}").strip()
      assert owner == "${secretOwner}", f"beta: expected owner '${secretOwner}', got '{owner}'"

      group = machine.succeed("stat -c '%G' ${pathB}").strip()
      assert group == "${secretGroup}", f"beta: expected group '${secretGroup}', got '{group}'"

      mode = str(int(machine.succeed("stat -c '%a' ${pathB}").strip()))
      assert mode == expected_mode, f"beta: expected mode '{expected_mode}', got '{mode}'"

      # Verify fileSecrets bridge: same files accessible through fileSecrets contract paths
      fs_content_a = machine.succeed("cat ${fsPathA}").strip()
      assert fs_content_a == "generated-alpha-secret", \
          f"fileSecrets alpha: expected 'generated-alpha-secret', got '{fs_content_a}'"

      fs_content_b = machine.succeed("cat ${fsPathB}").strip()
      assert fs_content_b == "generated-beta-secret", \
          f"fileSecrets beta: expected 'generated-beta-secret', got '{fs_content_b}'"
    '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
