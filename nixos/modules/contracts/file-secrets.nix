# The file secrets contract.
#
# A consumer needs a secret in a file with given permissions.
# A provider writes that file and tells the consumer its path.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  meta.maintainers = with lib.maintainers; [
    ibizaman
    kiara
  ];

  options.contracts.fileSecrets = lib.contract.mkContractOption {
    name = "fileSecrets";
    description = "A secret in a file, with given permissions.";

    # Each entry of `instances` imports this module.
    # A provider can add `default`, `defaultText` or `readOnly` to an option
    # through option declaration merging in `instances`.
    interface = {
      _file = ./file-secrets.nix;
      options = {
        request = mkOption {
          description = "Request of the file secrets contract: the consumer states the file permissions it needs.";
          type = types.submodule {
            options = {
              mode = mkOption {
                description = ''
                  Mode the secret file must have.
                '';
                type = types.str;
                default = "0400";
              };

              owner = mkOption {
                description = ''
                  POSIX user that must own the secret file.
                '';
                type = types.str;
              };

              group = mkOption {
                description = ''
                  POSIX group that must own the secret file.
                '';
                type = types.str;
              };
            };
          };
        };

        response = mkOption {
          description = "Response of the file secrets contract: the provider states where the file is.";
          type = types.submodule {
            options = {
              path = mkOption {
                type = types.str;
                description = ''
                  Path to the file containing the secret generated out of band.

                  This path will exist after deploying to a target host,
                  it is not available through the nix store.
                '';
              };
            };
          };
        };
      };
    };
  };
}
