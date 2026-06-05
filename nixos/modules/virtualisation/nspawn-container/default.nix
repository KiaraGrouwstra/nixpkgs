# This module creates a lightweight "container" from the NixOS configuration.
# Building the `config.system.build.nspawn` attribute gives you a command
# that starts a systemd-nspawn container running the NixOS configuration
# defined in `config`. By default, the Nix store is shared read-only with the
# host, which makes (re)building very efficient.
# This shares a lot in common with
# `nixos/modules/virtualisation/nixos-containers.nix`, but doesn't use systemd
# units.
# The networking options here match the options in
# `nixos/modules/virtualisation/nixos-containers.nix` which allows using these
# lightweight containers for nixos integration tests.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) types;
  cfg = config.virtualisation;
in
{
  options = {

    virtualisation.cmdline = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "systemd.unit=rescue.target"
        "systemd.log_level=debug"
        "systemd.log_target=console"
      ];
      description = ''
        Command line arguments to pass to the init process (likely systemd).
        Useful for debugging.
      '';
    };

    virtualisation.rootDir = lib.mkOption {
      type = types.str;
      default = "./${config.system.name}-root";
      defaultText = lib.literalExpression ''"./''${config.system.name}-root"'';
      description = ''
        Path to a directory for the root filesystem for the container.
        The directory will be created on startup if it does not
        exist.
      '';
    };

    virtualisation.systemd-nspawn = {

      package = lib.mkPackageOption pkgs "systemd" { };

      options = lib.mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "--bind=/home:/home" ];
        description = ''
          Options passed to systemd-nspawn.
          See [systemd-nspawn docs](https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html) for a complete list.
        '';
      };

    };

    virtualisation.writableStore = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the Nix store in the container is made writable: instead
        of bind-mounting the host's `/nix/store` read-only, the launcher
        stages a per-container store directory (bind-mounting each top-level
        host store entry into it as a real path) and binds that writable at
        `/nix/store`. This lets a deployment push new paths into the running
        container (e.g. via `nix-copy-closure --to`) at the cost of the
        read-only bind's efficiency.

        A writable overlayfs (the approach `qemu-vm.nix` uses) is not viable
        here: the kernel rejects an overlay upper inside the nested user
        namespaces of the Nix build sandbox, where these containers run.
      '';
    };
  };

  config = {
    boot.isNspawnContainer = true;

    assertions = [
      {
        assertion = config.specialisation == { };
        message = ''
          Setting 'specialisation' is disallowed for systemd-nspawn container configurations.
          Activating a specialisation requires creating SUID wrappers (e.g., for 'sudo'),
          which is prohibited within the Nix build sandbox where the test is run.
        '';
      }
      {
        # Check every interface defined in allInterfaces.
        # Containers try to create a bridge "${config.system.name}-${interfaceName}"
        assertion = lib.all (
          iface:
          let
            hostName = "${config.system.name}-${iface.name}";
          in
          lib.stringLength hostName <= 15
        ) (lib.attrValues cfg.allInterfaces);

        message =
          let
            offendingInterfaces = lib.filter (
              iface: lib.stringLength "${config.system.name}-${iface.name}" > 15
            ) (lib.attrValues cfg.allInterfaces);
            offenderList = map (
              i:
              "${config.system.name}-${i.name} (${toString (lib.stringLength "${config.system.name}-${i.name}")} chars)"
            ) offendingInterfaces;
          in
          ''
            The following generated host interface names exceed the Linux 15-character limit:
              ${lib.concatStringsSep "\n            " offenderList}

            Please shorten 'config.system.name' or the interface names in 'virtualisation.interfaces'.
          '';
      }
    ];

    virtualisation.systemd-nspawn.options = [
      "--private-network"
      "--machine=${config.system.name}"
    ]
    # With a writable store the wrapper below binds a per-container store
    # clone over `/nix/store`, so drop the read-only host-store bind here.
    ++ lib.optional (!cfg.writableStore) "--bind-ro=/nix/store:/nix/store"
    ++ [
      # systemd-nspawn does some cleverness to mount a procfs and sysfs in an
      # unprivileged container, see
      # <https://github.com/systemd/systemd/blob/v258.2/src/nspawn/nspawn.c#L4341-L4349>.
      # Unfortunately, this doesn't work in the Nix build sandbox as we do not
      # have permission to mount filesystems of type `sysfs` nor `procfs`.
      # Fortunately, the build sandbox does provide a `/proc` and `/sys` that
      # we can just forward onto the container.
      "--private-users=no"
      "--bind=/proc:/run/host/proc"
      "--bind=/sys:/run/host/sys"

      # From `man systemd-nspawn`:
      # > Use --keep-unit and --register=no in combination to disable any
      # > kind of unit allocation or registration with systemd-machined.
      "--keep-unit"
      "--register=no"

      # Send a READY=1 notification to a socket when the container is fully booted.
      "--notify-ready=yes"
    ];

    system.build.nspawn =
      let
        run-nspawn = pkgs.callPackage ./run-nspawn { };
        commandLineOptions = lib.cli.toCommandLineShellGNU { } {
          container-name = config.system.name;
          root-dir = cfg.rootDir;
          interfaces-json = builtins.toJSON (lib.attrValues cfg.allInterfaces);
          init = "${config.system.build.toplevel}/init";
          cmdline-json = builtins.toJSON cfg.cmdline;
        };

        # When the store is writable, stage a per-container store directory
        # before launching: bind-mount each top-level host store entry into
        # it as a real path (so the container sees real, not symlinked,
        # `/nix/store/<hash>` entries -- `nix-daemon` rejects symlinked
        # top-level entries, and `cp -al` fails cross-device against the
        # sandbox's separate store bind mount). New paths pushed in later
        # (e.g. by `nix-copy-closure --to`) land in the writable backing
        # alongside the bind-mounts. Staging runs on the host before
        # systemd-nspawn execs init, which itself lives under the store.
        stageWritableStore = ''
          : "''${RUN_NSPAWN_STORE_DIR:=$PWD/${config.system.name}-store}"
          if [ ! -e "$RUN_NSPAWN_STORE_DIR/.populated" ]; then
            ${pkgs.coreutils}/bin/mkdir -p "$RUN_NSPAWN_STORE_DIR"
            for entry in /nix/store/*; do
              name=''${entry##*/}
              target=$RUN_NSPAWN_STORE_DIR/$name
              if [ -L "$entry" ]; then
                # Preserve top-level symlinks as symlinks; nix-daemon
                # accepts these only when the original store has them.
                ${pkgs.coreutils}/bin/cp -P "$entry" "$target"
                continue
              fi
              if [ -d "$entry" ]; then
                ${pkgs.coreutils}/bin/mkdir "$target"
              else
                : > "$target"
              fi
              ${pkgs.util-linux}/bin/mount --bind "$entry" "$target"
            done
            : > "$RUN_NSPAWN_STORE_DIR/.populated"
          fi
        '';
        writableStoreBind = ''"--bind=$RUN_NSPAWN_STORE_DIR:/nix/store"'';
      in
      pkgs.writers.writeDashBin "run-${config.system.name}-nspawn" ''
        set -eu
        ${lib.optionalString cfg.writableStore stageWritableStore}
        exec ${lib.getExe run-nspawn} ${commandLineOptions} ${
          if cfg.writableStore then writableStoreBind else ""
        } \
          ${lib.escapeShellArgs config.virtualisation.systemd-nspawn.options} "$@"
      '';
  };
}
