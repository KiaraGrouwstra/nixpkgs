{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    bool
    str
    submodule
    ;
in
{
  meta = {
    description = ''
      Contract for delivering a set of secret values to a service as an
      environment file. A consumer requests one or more environment variables,
      each sourced from a secret at a given path, and a provider renders them
      into an `EnvironmentFile` attached to the consumer's systemd unit at
      runtime, reloading the unit when a value rotates.

      Unlike `fileSecrets` (a single file at a path), `envSecrets` expresses a
      whole set of variables bound to one unit, which is what services taking an
      `EnvironmentFile` (Mastodon, PeerTube, ...) need.
    '';
    maintainers = with lib.maintainers; [
      kiara
    ];
  };
  interface = {
    request = {
      unit = mkOption {
        description = ''
          Name of the systemd unit (without the `.service` suffix) the rendered
          environment file is attached to. The provider wires the unit to wait
          for the file and reload when any value rotates.
        '';
        type = str;
      };

      variables = mkOption {
        description = ''
          Environment variables to deliver, keyed by variable name. Each maps to
          a secret at the given `path`, reading the named `field`, optionally
          base64-decoding it.
        '';
        type = attrsOf (submodule {
          options = {
            path = mkOption {
              description = ''
                Provider-specific path to the secret holding this variable's
                value (e.g. a KV v2 read path for an OpenBao-backed provider).
              '';
              type = str;
            };

            field = mkOption {
              description = ''
                Field within the secret at `path` holding the value.
              '';
              type = str;
              default = "content";
            };

            base64Decode = mkOption {
              description = ''
                Whether the field value is base64-encoded and must be decoded
                before being written into the environment file.
              '';
              type = bool;
              default = true;
            };
          };
        });
      };
    };
    result = {
      unit = mkOption {
        type = str;
        description = ''
          Name of the systemd unit (without the `.service` suffix) the rendered
          environment file is attached to.
        '';
      };

      environmentFile = mkOption {
        type = str;
        description = ''
          Path to the rendered environment file. This path will exist after
          deploying to a target host; it is not available through the nix store.
        '';
      };
    };
  };
  behaviorTest =
    {
      name,
      wantPath,
      extraModules ? [ ],
    }:
    lib.contract.mkBehaviorTest {
      contractName = "envSecrets";
      testName = name;
      inherit wantPath extraModules;
      nodeModule =
        { ... }:
        {
          options.test = { };
        };
      requestOf = _config: { };
      testScript =
        { ... }:
        ''
          machine.succeed("true")
        '';
    };
}
