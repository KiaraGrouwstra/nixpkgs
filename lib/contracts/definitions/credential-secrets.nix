# The credential secrets contract.
#
# A consumer is a systemd unit that loads a secret with `LoadCredential=`.
# A provider supplies the source of the credential: a regular file or an
# `AF_UNIX` stream socket.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  meta = {
    description = "A secret that a systemd unit loads as a credential.";
    maintainers = with lib.maintainers; [
      ibizaman
      kiara
    ];
  };

  # Both sides import this module into a submodule type.
  # Refer to `./file-secrets.nix` for how each side adds a `default`.
  interface = {
    _file = ./credential-secrets.nix;
    options = {
      request = mkOption {
        description = "Request of the credential secrets contract: the consumer states which unit loads the credential.";
        type = types.submodule {
          options = {
            unit = mkOption {
              description = ''
                Name of the systemd unit that loads the credential, with its suffix.
              '';
              example = "stash.service";
              type = types.str;
            };

            id = mkOption {
              description = ''
                ID of the credential in `LoadCredential=` of the unit.
              '';
              example = "password";
              type = types.str;
            };
          };
        };
      };

      response = mkOption {
        description = "Response of the credential secrets contract: the provider states the source of the credential.";
        type = types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = ''
                Absolute path to a regular file or to an `AF_UNIX` stream socket that contains the secret.

                The consumer must load the secret with `LoadCredential=<id>:<path>`,
                and must not open the path itself.
                systemd reads the source as root, and gives the secret to the unit in `$CREDENTIALS_DIRECTORY/<id>`.

                For a socket, systemd connects from an abstract socket address
                with the name `<NUL><random>/unit/<unit>/<id>`.
                The provider can get this name with `getpeername(2)`,
                and use it to send the secret only to the unit and ID in `request`.
                Each process can bind each abstract socket address,
                thus the provider must also make sure that only root can connect to the socket.

                This path will exist after deploying to a target host,
                it is not available through the nix store.
              '';
            };
          };
        };
      };
    };
  };
}
