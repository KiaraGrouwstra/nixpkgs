# A provider of the file secrets contract is also a provider of the credential secrets contract,
# because a regular file is a valid source of a credential.
# systemd reads the source as root, thus the file can stay at the default owner root.
args@{ lib, ... }:
let
  test = import ./test.nix args;
  content = "a super secret secret!";
in
test {
  name = "filesecrets-provider";
  inherit content;
  providerRoot = [
    "testing"
    "hardcoded-secret"
    "fileSecrets"
    "mysecret"
  ];
  providerRequest = _: { };
  extraModules = [
    ../../../modules/testing/hardcoded-secret.nix
    { testing.hardcoded-secret.fileSecrets.mysecret.providerOptions.content = content; }
  ];
}
// {
  meta.maintainers = with lib.maintainers; [
    ibizaman
    kiara
  ];
}
