{ runTest }:
{
  chaining = runTest ./chaining.nix;
  child-service-locality = runTest ./child-service-locality.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
}
