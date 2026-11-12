args@{ lib, ... }:
let
  test = import ./test.nix args;
  content = "a super secret secret!";
in
test {
  name = "hardcoded-secret";
  inherit content;
  providerRoot = [
    "testing"
    "hardcoded-secret"
    "credentialSecrets"
    "mysecret"
  ];
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    {
      testing.hardcoded-secret.credentialSecrets.mysecret.providerOptions.content = content;

      # A unit that the request does not name.
      systemd.services.credential-intruder.serviceConfig = {
        Type = "oneshot";
        LoadCredential = "secret:/run/hardcodedsecrets/mysecret.sock";
        ExecStart = "true";
      };
    }
  ];
  extraTestScript = ''
    machine.fail("systemctl start credential-intruder.service")
    machine.succeed("journalctl -u 'hardcodedcredential_mysecret@*' | grep -F 'Refused the credential'")
  '';
}
// {
  meta.maintainers = with lib.maintainers; [
    ibizaman
    kiara
  ];
}
