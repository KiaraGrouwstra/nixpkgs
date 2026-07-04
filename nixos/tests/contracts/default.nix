{ runTest }:
{
  chaining = runTest ./chaining.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  systemd-openbaod = runTest ./systemd-openbaod.nix;
  filebackup-hardcoded-file-backup = runTest ./filebackup/hardcoded-file-backup.nix;
  filebackup-borgbackup = runTest ./filebackup/borgbackup.nix;
  filebackup-restic = runTest ./filebackup/restic.nix;
  ssl-self-signed = runTest ./ssl/self-signed-ssl.nix;
  smtp-opensmtpd = runTest ./smtp/opensmtpd.nix;
  ldap-openldap = runTest ./ldap/openldap.nix;
  oidc-dex = runTest ./oidc/dex.nix;
  s3-minio = runTest ./s3/minio.nix;
  streamingbackup-hardcoded = runTest ./streamingbackup/hardcoded-streaming-backup.nix;
  streamingbackup-restic = runTest ./streamingbackup/restic.nix;
  generatefiles-vars = runTest ./generatefiles/vars.nix;
  generatefiles-vars-openbao = runTest ./generatefiles/vars-openbao.nix;
}
