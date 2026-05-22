{ runTest }:
{
  chaining = runTest ./chaining.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  filesecrets-hardcoded-secret-want = runTest ./filesecrets/hardcoded-secret-want.nix;
}
