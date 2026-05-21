{ runTest }:
{
  chaining = runTest ./chaining.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  cross-node-modular-services-direct = runTest ./cross-node-modular-services-direct.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
}
