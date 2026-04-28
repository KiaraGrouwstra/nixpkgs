{ runTest }:
{
  chaining = runTest ./chaining.nix;
  cross-node = runTest ./cross-node.nix;
  database-modular-services = runTest ./database-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  systemd-openbaod = runTest ./systemd-openbaod.nix;
  filebackup-hardcoded-file-backup = runTest ./filebackup/hardcoded-file-backup.nix;
  filebackup-restic = runTest ./filebackup/restic.nix;
  ssl-self-signed = runTest ./ssl/self-signed-ssl.nix;
  smtp-hardcoded = runTest ./smtp/hardcoded-smtp.nix;
  ldap-hardcoded = runTest ./ldap/hardcoded-ldap.nix;
  collision = runTest ./collision-test.nix;
  modular-services = runTest ./modular-services.nix;
  nested-services = runTest ./nested-services.nix;
  nixos-provider-modular-consumer = runTest ./nixos-provider-modular-consumer.nix;
}
