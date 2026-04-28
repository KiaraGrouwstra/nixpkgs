# collection of contract templates, defined in `lib` so we can still build the manual.
# declarations of individual contracts follow the type in `./definition-type.nix`.
{ lib, ... }:
lib.mapAttrs (
  _: path:
  lib.evalOption (lib.mkOption { type = lib.contract.definitionType; }) (import path { inherit lib; })
) {
  fileSecrets = ./file-secrets.nix;
  fileBackup = ./file-backup.nix;
  ssl = ./ssl.nix;
  smtp = ./smtp.nix;
  ldap = ./ldap.nix;
  sso = ./sso.nix;
  s3 = ./s3.nix;
  streamingBackup = ./streaming-backup.nix;
}
