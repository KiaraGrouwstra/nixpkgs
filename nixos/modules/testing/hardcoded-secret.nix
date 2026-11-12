{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-secret;

  inherit (lib)
    mapAttrs'
    mkOption
    nameValuePair
    escapeShellArgs
    ;
  inherit (lib.types)
    attrsOf
    str
    submodule
    ;
  inherit (pkgs) writeText;

  providerOptions = mkOption {
    description = "Options of this provider that are not part of the contract.";
    default = { };
    type = submodule {
      options.content = mkOption {
        type = str;
        description = ''
          Content of the secret as a string.

          This will be stored in the nix store and should only be used for testing or maybe in dev.
        '';
      };
    };
  };

  # Sends the secret to one connection, if the peer is the unit and ID of the request.
  # Arguments: the unit, the credential ID and the file with the content.
  serveCredential = writeText "hardcoded-credential.py" ''
    import socket
    import sys

    unit, credential_id, content = sys.argv[1:]
    conn = socket.socket(fileno=0)
    peer = conn.getpeername()
    if isinstance(peer, str):
        peer = peer.encode()
    # The name is NUL, a random string, "/unit/", the unit, "/" and the ID.
    _, _, peer_request = peer.partition(b"/")
    if peer_request != f"unit/{unit}/{credential_id}".encode():
        sys.exit(f"Refused the credential to the peer {peer!r}")
    with open(content, "rb") as f:
        conn.sendall(f.read())
  '';
in
{
  options.testing.hardcoded-secret = {
    directory = mkOption {
      type = str;
      default = "/run/hardcodedsecrets";
      description = ''
        Directory in which the provider writes the secret files.
        Each secret file has the name of its entry in
        [](#opt-testing.hardcoded-secret.fileSecrets).
      '';
    };

    fileSecrets = mkOption {
      default = { };
      description = ''
        Hardcoded file secrets. These should only be used in tests.

        They aim to replace the usage of pkgs.writeText in NixOS VM tests
        as those make the file world readable
        while this module set runtime permissions on the file.
        This makes the tests more accurate, ensuring the permissions
        set by the contract consumer are correct.

        For each entry, a service writes `providerOptions.content` to `response.path`,
        with the `mode`, `owner` and `group` from `request`.
        The service runs after `systemd-sysusers` or `userborn`, and before `sysinit.target`,
        thus the file exists before the services that use it start.
        The content is also in the Nix store, where each user can read it.
      '';
      example = lib.literalExpression ''
        {
          mySecret = {
            request = {
              owner = "me";
              group = "me";
              mode = "0400";
            };
            providerOptions.content = "My Secret";
          };
        }
      '';
      type = attrsOf (
        submodule (
          { name, ... }:
          {
            imports = [ lib.contracts.fileSecrets.interface ];

            options = {
              request = mkOption {
                type = submodule {
                  options = {
                    owner = mkOption { default = "root"; };
                    group = mkOption { default = "root"; };
                  };
                };
              };

              response = mkOption {
                default = { };
                type = submodule {
                  options.path = mkOption {
                    default = "${cfg.directory}/${name}";
                    defaultText = lib.literalExpression ''"''${config.testing.hardcoded-secret.directory}/<name>"'';
                  };
                };
              };

              inherit providerOptions;
            };
          }
        )
      );
    };

    credentialSecrets = mkOption {
      default = { };
      description = ''
        Hardcoded credential secrets. These should only be used in tests.

        For each entry, a socket unit listens on `response.path`, and only root can connect to it.
        For each connection, a service sends `providerOptions.content`,
        if the peer is the unit and the credential ID in `request`.
        The content is also in the Nix store, where each user can read it.
      '';
      example = lib.literalExpression ''
        {
          mySecret = {
            request = {
              unit = "my-service.service";
              id = "password";
            };
            providerOptions.content = "My Secret";
          };
        }
      '';
      type = attrsOf (
        submodule (
          { name, ... }:
          {
            imports = [ lib.contracts.credentialSecrets.interface ];

            options = {
              response = mkOption {
                default = { };
                type = submodule {
                  options.path = mkOption {
                    default = "${cfg.directory}/${name}.sock";
                    defaultText = lib.literalExpression ''"''${config.testing.hardcoded-secret.directory}/<name>.sock"'';
                  };
                };
              };

              inherit providerOptions;
            };
          }
        )
      );
    };
  };

  config.systemd.sockets = mapAttrs' (
    n: cfg':
    nameValuePair "hardcodedcredential_${n}" {
      description = "Hardcoded credential ${n}";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg'.response.path ];
      socketConfig = {
        Accept = true;
        # Only root can connect, thus only systemd can give an abstract socket address of a unit.
        SocketMode = "0600";
      };
    }
  ) cfg.credentialSecrets;

  config.systemd.services = lib.mkMerge [
    (mapAttrs' (
      n: cfg':
      nameValuePair "hardcodedcredential_${n}@" {
        description = "Hardcoded credential ${n}";
        serviceConfig = {
          ExecStart = "${pkgs.python3Minimal.interpreter} ${serveCredential} ${
            escapeShellArgs [
              cfg'.request.unit
              cfg'.request.id
              (writeText "hardcodedcredential_${n}_content" cfg'.providerOptions.content)
            ]
          }";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
        };
      }
    ) cfg.credentialSecrets)

    # Write each secret in a service and not in an activation script.
    # An activation script can run before the owner of the secret exists:
    # activation scripts without dependencies run in alphabetical order,
    # and `systemd-sysusers` and `userborn` create users after activation.
    # The services run before `sysinit.target`, thus before all services
    # that have default dependencies, such as the consumers of the secrets.
    (mapAttrs' (
      n: cfg':
      let
        source = writeText "hardcodedsecret_${n}_content" cfg'.providerOptions.content;

        inherit (cfg') request response;
      in
      nameValuePair "hardcodedsecret_${n}" {
        description = "Hardcoded secret ${n}";
        wantedBy = [ "sysinit.target" ];
        after = [
          "local-fs.target"
          "systemd-sysusers.service"
          "userborn.service"
        ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        conflicts = [ "shutdown.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          install -D -m ${request.mode} -o ${request.owner} -g ${request.group} \
            ${source} "${response.path}"
        '';
      }
    ) cfg.fileSecrets)
  ];
}
