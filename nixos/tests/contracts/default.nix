{ runTest }:
{
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  modular-services = runTest ./modular-services.nix;
}
