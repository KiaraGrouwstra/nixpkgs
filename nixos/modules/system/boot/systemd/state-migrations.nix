{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    concatMapStrings
    escapeShellArg
    filter
    literalExpression
    mapAttrs'
    mkIf
    mkOption
    nameValuePair
    optionalString
    types
    ;

  cfg = config.systemd.stateMigrations;

  enabled = lib.filterAttrs (_: m: m.enable) cfg;

  stepType = types.submodule {
    options = {
      version = mkOption {
        type = types.str;
        description = ''
          Application version this step migrates *to*. The step runs when the
          recorded version is older than this and the version being deployed is
          this one or newer.
        '';
        example = "4.4.0";
      };

      description = mkOption {
        type = types.str;
        default = "";
        description = ''
          Human-readable summary of what the step does. Written to the journal
          before the step runs.
        '';
      };

      phase = mkOption {
        type = types.enum [
          "pre"
          "post"
        ];
        default = "pre";
        description = ''
          Whether the step runs before the application units are (re)started
          (`pre`) or after (`post`).

          Note that a `post` step must not assume the application is already
          serving traffic: an ordering dependency on a `Type=simple` unit is
          satisfied as soon as that unit forks, not once it is ready.
        '';
      };

      script = mkOption {
        type = types.lines;
        description = ''
          Shell commands performing the migration. Run as a separate script
          with `set -e`, so any failing command aborts the step.
        '';
      };

      backup = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Shell commands run immediately before {option}`script`, meant to save
          whatever {option}`script` is about to change. The directory to write
          to is passed in the `BACKUP` environment variable; it is created
          empty beforehand.
        '';
      };

      restore = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Shell commands run when {option}`script` fails, meant to undo it from
          the contents of `BACKUP`. The migration is aborted afterwards either
          way.
        '';
      };

      warn = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Warning logged before the step runs. Use it for steps that discard or
          rewrite data irreversibly.
        '';
      };
    };
  };

  migrationType = types.submodule (
    { name, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to run these migrations. Modules that expose an
            `automaticMigrations` setting of their own should point it here.
          '';
        };

        version = mkOption {
          type = types.str;
          description = ''
            Version of the application that is being deployed, normally
            `cfg.package.version`. Migrations advance the recorded state from
            whatever was deployed last to this version.
          '';
          example = literalExpression "config.services.pixelfed.package.version";
        };

        stateFile = mkOption {
          type = types.path;
          description = ''
            File recording which version the on-disk state belongs to. It must
            live on the same persistent storage as the state itself, so that
            restoring a backup of the state also restores the record of its
            version.
          '';
          example = "/var/lib/pixelfed/.nixos-state-migration";
        };

        freshInstallTest = mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = ''
            Shell commands deciding whether the installation holds no data yet.
            Exit status 0 means "fresh", 1 means "already has data", and any
            other status means the question could not be answered and aborts
            the migration.

            This is only consulted when {option}`stateFile` does not exist,
            which happens on a genuinely new installation *and* on the first
            deployment of these migrations onto a pre-existing one. Without a
            test, both are treated as fresh installations. Any module whose
            {option}`onFreshInstall` would destroy existing data must set this.

            The commands are run as a separate script without `set -e`, because
            their exit status is the answer.
          '';
        };

        onFreshInstall = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Shell commands initialising a brand-new installation. Run instead
            of {option}`steps` and {option}`onUpgrade`, in the `pre` phase.
          '';
        };

        onUpgrade = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Shell commands run on every version increase, in the `pre` phase
            after all in-range `pre` steps. Use it for work that is required by
            each upgrade rather than by one particular version, such as running
            the application's own migration tool.
          '';
        };

        onUpgradePost = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Counterpart of {option}`onUpgrade` for the `post` phase, run after
            all in-range `post` steps.
          '';
        };

        backup = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Shell commands run once per upgrade, in the `pre` phase before any
            step and before {option}`onUpgrade`. The directory to write to is
            passed in the `BACKUP` environment variable; it is created empty
            beforehand.

            Unlike {option}`steps.*.backup` this has no `restore` counterpart,
            because it is meant for applications that migrate their own state
            out of this module's sight: there is no failure for the module to
            react to, and the backup is there for the operator instead.
          '';
        };

        steps = mkOption {
          type = types.listOf stepType;
          default = [ ];
          description = ''
            Version-keyed migration steps. Within a phase they run in the order
            they are declared, and only those whose {option}`version` lies
            above the recorded version and at or below {option}`version`.
          '';
        };

        onDowngrade = mkOption {
          type = types.enum [
            "refuse"
            "warn"
            "ignore"
          ];
          default = "refuse";
          description = ''
            What to do when the deployed version is older than the recorded
            one. `refuse` fails the migration, and with it the application
            units ordered after it. `warn` and `ignore` both record the older
            version and run nothing.
          '';
        };

        maxSkip = mkOption {
          type = types.nullOr (
            types.enum [
              "major"
              "minor"
            ]
          );
          default = null;
          description = ''
            Refuse to upgrade when an entire release series is skipped, for
            applications that only support upgrading one series at a time.
            `minor` additionally requires that no minor series is skipped.
          '';
        };

        before = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Application units that must not start until the `pre` phase has
            succeeded. They gain `Requires=` on the `pre` unit, so a failed
            migration keeps them stopped, and `Wants=` on the `post` unit.
          '';
          example = [ "phpfpm-pixelfed.service" ];
        };

        after = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Units both generated units are ordered after, such as whatever
            prepares the application's configuration file.
          '';
        };

        requires = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Units both generated units depend on.";
        };

        backupDir = mkOption {
          type = types.path;
          default = "/var/lib/nixos/state-migrations/${name}";
          defaultText = literalExpression ''"/var/lib/nixos/state-migrations/''${name}"'';
          description = ''
            Directory under which {option}`backup` and {option}`steps.*.backup`
            write. It must be on persistent storage rather than a tmpfs, and
            writable by the user the migration units run as. Only created when
            a backup is actually declared.
          '';
        };

        serviceConfig = mkOption {
          type = types.attrs;
          default = { };
          description = ''
            Extra service configuration for both generated units. `Type`,
            `RemainAfterExit` and `ExecStart` are set by this module.
          '';
        };

        path = mkOption {
          type = types.listOf (types.either types.package types.str);
          default = [ ];
          description = "Packages added to `PATH` for both generated units.";
        };

        environment = mkOption {
          type = types.attrsOf (
            types.nullOr (
              types.oneOf [
                types.str
                types.path
                types.package
              ]
            )
          );
          default = { };
          description = "Environment variables set for both generated units.";
        };
      };
    }
  );

  # Only the migration's own helpers rely on this; appended so that anything a
  # module puts in `path` keeps precedence.
  runnerPath = lib.makeBinPath [ pkgs.coreutils ];

  mkScript = name: text: pkgs.writeShellScript name ("set -e\n" + text);

  renderStep =
    name: m: step:
    let
      slug = "${name}-${lib.replaceStrings [ "." ] [ "_" ] step.version}-${step.phase}";
      backupPath = "${m.backupDir}/${step.version}";
    in
    ''
      if in_range ${escapeShellArg step.version}; then
        ${optionalString (step.warn != null) "log ${escapeShellArg "WARNING: ${step.warn}"}"}
        log ${escapeShellArg "running step ${step.version}${optionalString (step.description != "") ": ${step.description}"}"}
        ${optionalString (step.backup != "") ''
          BACKUP=${escapeShellArg backupPath}
          export BACKUP
          rm -rf "$BACKUP"
          mkdir -p "$BACKUP"
          ${mkScript "${slug}-backup" step.backup}
        ''}
        if ${mkScript "${slug}-up" step.script}; then
          log ${escapeShellArg "step ${step.version} succeeded"}
        else
          log ${escapeShellArg "step ${step.version} FAILED"}
          ${optionalString (step.restore != "") ''
            log ${escapeShellArg "restoring from ${backupPath}"}
            ${mkScript "${slug}-restore" step.restore}
          ''}
          exit 1
        fi
      fi
    '';

  renderPhase =
    name: m: phase:
    concatMapStrings (renderStep name m) (filter (s: s.phase == phase) m.steps);

  hasPost = m: m.onUpgradePost != "" || lib.any (s: s.phase == "post") m.steps;

  # One script for both units; the phase is the sole argument.
  runner =
    name: m:
    pkgs.writeShellScript "${name}-state-migration" ''
      set -e

      export PATH="''${PATH:+$PATH:}${runnerPath}"

      PHASE="$1"
      MIGRATION_NAME=${escapeShellArg name}
      MIGRATION_TO=${escapeShellArg m.version}
      STATE_FILE=${escapeShellArg (toString m.stateFile)}
      export MIGRATION_NAME MIGRATION_TO

      log() {
        echo "state-migration[$MIGRATION_NAME/$PHASE]: $*"
      }

      # True when $1 sorts strictly before $2.
      version_lt() {
        [ "$1" != "$2" ] &&
          [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
      }

      # True when $1 is newer than what is recorded and not newer than the
      # version being deployed.
      in_range() {
        version_lt "$FROM" "$1" && ! version_lt "$MIGRATION_TO" "$1"
      }

      # Leading numeric run of the Nth dot-separated field, 0 when absent.
      version_field() {
        local f
        f="$(printf '%s' "$1" | cut -d. -f"$2" | tr -cd '0-9')"
        printf '%s' "''${f:-0}"
      }

      read_stamp() {
        stamped_version=""
        stamped_phase=""
        stamped_previous=""
        [ -e "$STATE_FILE" ] || return 0
        while IFS='=' read -r key value; do
          case "$key" in
            version) stamped_version="$value" ;;
            phase) stamped_phase="$value" ;;
            previous) stamped_previous="$value" ;;
          esac
        done < "$STATE_FILE"
      }

      write_stamp() {
        mkdir -p "$(dirname "$STATE_FILE")"
        {
          printf 'version=%s\n' "$1"
          printf 'phase=%s\n' "$2"
          if [ -n "''${3:-}" ]; then
            printf 'previous=%s\n' "$3"
          fi
        } > "$STATE_FILE.tmp"
        mv -f "$STATE_FILE.tmp" "$STATE_FILE"
      }

      read_stamp

      if [ -z "$stamped_version" ]; then
        if [ "$PHASE" != pre ]; then
          exit 0
        fi
        ${
          if m.freshInstallTest == null then
            "fresh=1"
          else
            ''
              if ${pkgs.writeShellScript "${name}-fresh-install-test" m.freshInstallTest}; then
                fresh=1
              else
                status=$?
                if [ "$status" -gt 1 ]; then
                  log "cannot tell whether this installation is fresh: the test exited with status $status"
                  exit "$status"
                fi
                fresh=0
              fi
            ''
        }
        if [ "$fresh" -eq 1 ]; then
          log "fresh installation, initialising at version $MIGRATION_TO"
          ${optionalString (m.onFreshInstall != "") (mkScript "${name}-fresh-install" m.onFreshInstall)}
        else
          log "existing installation without a recorded version, recording $MIGRATION_TO without migrating"
        fi
        write_stamp "$MIGRATION_TO" complete
        exit 0
      fi

      if [ "$stamped_version" = "$MIGRATION_TO" ]; then
        if [ "$stamped_phase" = complete ]; then
          log "state is already at version $MIGRATION_TO"
          exit 0
        fi
        if [ "$PHASE" = pre ]; then
          log "pre phase for version $MIGRATION_TO already completed"
          exit 0
        fi
        FROM="$stamped_previous"
        MIGRATION_FROM="$FROM"
        export MIGRATION_FROM
        log "running post-deploy migrations from $FROM to $MIGRATION_TO"
        ${renderPhase name m "post"}
        ${optionalString (m.onUpgradePost != "") (mkScript "${name}-on-upgrade-post" m.onUpgradePost)}
        write_stamp "$MIGRATION_TO" complete
        exit 0
      fi

      if version_lt "$MIGRATION_TO" "$stamped_version"; then
        if [ "$PHASE" != pre ]; then
          exit 0
        fi
        ${
          {
            refuse = ''
              log "refusing to move from version $stamped_version back to $MIGRATION_TO: these migrations are one-way"
              exit 1
            '';
            warn = ''
              log "WARNING: moving from version $stamped_version back to $MIGRATION_TO without migrating; state may be incompatible"
              write_stamp "$MIGRATION_TO" complete
              exit 0
            '';
            ignore = ''
              write_stamp "$MIGRATION_TO" complete
              exit 0
            '';
          }
          .${m.onDowngrade}
        }
      fi

      if [ "$stamped_phase" != complete ]; then
        log "the upgrade to $stamped_version never finished its post-deploy phase; refusing to upgrade to $MIGRATION_TO on top of it"
        log "redeploy version $stamped_version to retry it, or fix $STATE_FILE by hand"
        exit 1
      fi

      if [ "$PHASE" != pre ]; then
        exit 0
      fi

      FROM="$stamped_version"
      MIGRATION_FROM="$FROM"
      export MIGRATION_FROM

      ${optionalString (m.maxSkip != null) ''
        from_major="$(version_field "$FROM" 1)"
        to_major="$(version_field "$MIGRATION_TO" 1)"
        from_minor="$(version_field "$FROM" 2)"
        to_minor="$(version_field "$MIGRATION_TO" 2)"
        if [ "$((to_major - from_major))" -gt 1 ]; then
          log "refusing to upgrade from $FROM to $MIGRATION_TO: at least one major release series is skipped"
          exit 1
        fi
        ${optionalString (m.maxSkip == "minor") ''
          if [ "$to_major" -eq "$from_major" ] && [ "$((to_minor - from_minor))" -gt 1 ]; then
            log "refusing to upgrade from $FROM to $MIGRATION_TO: at least one minor release series is skipped"
            exit 1
          fi
          if [ "$((to_major - from_major))" -eq 1 ] && [ "$to_minor" -gt 0 ]; then
            log "refusing to upgrade from $FROM to $MIGRATION_TO: at least one minor release series is skipped"
            exit 1
          fi
        ''}
      ''}

      log "migrating from $FROM to $MIGRATION_TO"
      ${optionalString (m.backup != "") ''
        BACKUP=${escapeShellArg "${m.backupDir}/upgrade-${m.version}"}
        export BACKUP
        rm -rf "$BACKUP"
        mkdir -p "$BACKUP"
        log "backing up into $BACKUP"
        ${mkScript "${name}-backup" m.backup}
      ''}
      ${renderPhase name m "pre"}
      ${optionalString (m.onUpgrade != "") (mkScript "${name}-on-upgrade" m.onUpgrade)}
      write_stamp "$MIGRATION_TO" ${if hasPost m then ''pre "$FROM"'' else "complete"}
    '';

  commonUnit = name: m: phase: {
    inherit (m) path environment;
    serviceConfig = {
      SyslogIdentifier = "${name}-migrate-${phase}";
    }
    // m.serviceConfig
    // {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  preUnits = mapAttrs' (
    name: m:
    nameValuePair "${name}-migrate-pre" (
      lib.recursiveUpdate (commonUnit name m "pre") {
        description = "State migrations for ${name} (pre-deploy)";
        wantedBy = [ "multi-user.target" ];
        inherit (m) after requires;
        before = m.before;
        requiredBy = m.before;
        serviceConfig.ExecStart = "${runner name m} pre";
      }
    )
  ) enabled;

  postUnits = mapAttrs' (
    name: m:
    nameValuePair "${name}-migrate-post" (
      lib.recursiveUpdate (commonUnit name m "post") {
        description = "State migrations for ${name} (post-deploy)";
        wantedBy = m.before ++ [ "multi-user.target" ];
        after = m.after ++ [ "${name}-migrate-pre.service" ] ++ m.before;
        requires = m.requires ++ [ "${name}-migrate-pre.service" ];
        serviceConfig.ExecStart = "${runner name m} post";
      }
    )
  ) (lib.filterAttrs (_: hasPost) enabled);
in
{
  options.systemd.stateMigrations = mkOption {
    type = types.attrsOf migrationType;
    default = { };
    description = ''
      Migrations that bring state persisted by an application from the version
      that was deployed last to the version being deployed now, keyed on the
      application's own version.

      Each entry generates a `<name>-migrate-pre.service` and, when any `post`
      work is declared, a `<name>-migrate-post.service`. Both are
      `Type=oneshot`, so the units listed in {option}`before` are genuinely
      held back until the pre-deploy phase has exited.

      The version the state belongs to is recorded in {option}`stateFile`
      alongside the state itself. Do not confuse this with
      {option}`system.moduleStateRevisions`, which tracks the *NixOS* release
      at which a module changed how it persists state and whose migrations are
      performed by the user.
    '';
  };

  config = mkIf (enabled != { }) {
    assertions = lib.mapAttrsToList (name: m: {
      assertion = m.version != "";
      message = "systemd.stateMigrations.${name}.version must not be empty.";
    }) enabled;

    systemd.services = preUnits // postUnits;
  };
}
