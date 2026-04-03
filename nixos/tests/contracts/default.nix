{ runTest }:
{
  cross-node = runTest ./cross-node.nix;
  database-modular-services = runTest ./database-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  modular-services = runTest ./modular-services.nix;
}
