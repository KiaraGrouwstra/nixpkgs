{ runTest }:
{
  chaining = runTest ./chaining.nix;
  service-locality-parent-child = runTest ./service-locality/parent-child.nix;
  service-locality-peer = runTest ./service-locality/peer.nix;
  service-locality-cross-node = runTest ./service-locality/cross-node.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
}
