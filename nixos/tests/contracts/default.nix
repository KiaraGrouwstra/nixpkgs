{ runTest }:
{
  credentialsecrets-filesecrets-provider = runTest ./credentialsecrets/filesecrets-provider.nix;
  credentialsecrets-hardcoded-secret = runTest ./credentialsecrets/hardcoded-secret.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  filesecrets-hardcoded-secret-userborn = runTest ./filesecrets/hardcoded-secret-userborn.nix;
}
