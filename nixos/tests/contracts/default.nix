{ runTest }:
{
  cross-node = runTest ./cross-node.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  modular-services = runTest ./modular-services.nix;
}
