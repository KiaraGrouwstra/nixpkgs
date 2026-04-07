{ runTest }:
{
  chaining = runTest ./chaining.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  systemd-openbaod = runTest ./systemd-openbaod.nix;
  filebackup-hardcoded-file-backup = runTest ./filebackup/hardcoded-file-backup.nix;
  filebackup-restic = runTest ./filebackup/restic.nix;
}
