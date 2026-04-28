{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    bool
    listOf
    package
    str
    submodule
    ;
in
{
  meta = {
    description = ''
      Contract for declarative file generation where a consumer provides
      a script that produces named files and a provider handles generation,
      storage, and provisioning with the requested permissions.
    '';
    maintainers = with lib.maintainers; [
      kiara
    ];
  };
  interface = {
    request = {
      files = mkOption {
        description = ''
          Files to generate. Keys are file names the script must produce under `$out/`.
        '';
        type = attrsOf (submodule {
          options = {
            secret = mkOption {
              description = "Whether the file contains sensitive data.";
              type = bool;
              default = true;
            };
            owner = mkOption {
              description = "Unix user that must own the generated file.";
              type = str;
              default = "root";
            };
            group = mkOption {
              description = "Unix group that must own the generated file.";
              type = str;
              default = "root";
            };
            mode = mkOption {
              description = "File permissions as an octal string.";
              type = str;
              default = "0400";
            };
          };
        });
      };
      script = mkOption {
        description = ''
          Shell script that generates the requested files.
          The script must write each declared file to `$out/<name>`.
          Dependency outputs (from `dependencies`) are available under `$in/<dep>/`.
        '';
        type = str;
      };
      runtimeInputs = mkOption {
        description = ''
          Packages available in `PATH` during script execution.
        '';
        type = listOf package;
        default = [ ];
      };
      dependencies = mkOption {
        description = ''
          Names of other generateFiles instances whose outputs
          are made available under `$in/<name>/` when the script runs.
        '';
        type = listOf str;
        default = [ ];
      };
    };
    result = {
      files = mkOption {
        description = ''
          Generated files with their provisioned paths.
        '';
        type = attrsOf (submodule {
          options.path = mkOption {
            description = "Path to the generated file on the target system.";
            type = str;
          };
        });
      };
    };
  };
  behaviorTest =
    {
      name,
      providerRoot,
      extraModules ? [ ],
    }:
    {
      name = "contracts_generatefiles_${name}";
      containers.machine =
        { config, ... }:
        {
          imports = extraModules;

          options.test = {
            owner = mkOption {
              type = str;
              default = "root";
            };

            group = mkOption {
              type = str;
              default = "root";
            };

            mode = mkOption {
              type = str;
              default = "0400";
            };

            contentA = mkOption {
              type = str;
              default = "generated-secret-A";
            };

            contentB = mkOption {
              type = str;
              default = "generated-secret-B";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                files = {
                  fileA = {
                    inherit (config.test) owner group mode;
                  };
                  fileB = {
                    inherit (config.test) owner group mode;
                  };
                };
                script = ''
                  echo -n "${config.test.contentA}" > "$out"/fileA
                  echo -n "${config.test.contentB}" > "$out"/fileB
                '';
              };
            })
            (lib.mkIf (config.test.owner != "root") {
              users.users.${config.test.owner}.isNormalUser = true;
            })
            (lib.mkIf (config.test.group != "root") {
              users.groups.${config.test.group} = { };
            })
          ];
        };

      testScript =
        { containers, ... }:
        let
          cfg = containers.machine;
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          # Wait for the generation service to complete
          machine.wait_for_unit("generate-vars.service")

          for file_name, expected_content in [("fileA", "${cfg.test.contentA}"), ("fileB", "${cfg.test.contentB}")]:
              path = {
                  "fileA": "${result.files.fileA.path}",
                  "fileB": "${result.files.fileB.path}",
              }[file_name]

              machine.succeed(f"test -f {path}")

              owner = machine.succeed(f"stat -c '%U' {path}").strip()
              print(f"{file_name}: owner={owner}")
              if owner != "${cfg.test.owner}":
                  raise Exception(f"{file_name}: owner should be '${cfg.test.owner}' but got '{owner}'")

              group = machine.succeed(f"stat -c '%G' {path}").strip()
              print(f"{file_name}: group={group}")
              if group != "${cfg.test.group}":
                  raise Exception(f"{file_name}: group should be '${cfg.test.group}' but got '{group}'")

              mode = str(int(machine.succeed(f"stat -c '%a' {path}").strip()))
              print(f"{file_name}: mode={mode}")
              wanted_mode = str(int("${cfg.test.mode}"))
              if mode != wanted_mode:
                  raise Exception(f"{file_name}: mode should be '{wanted_mode}' but got '{mode}'")

              content = machine.succeed(f"cat {path}").strip()
              print(f"{file_name}: content={content}")
              if content != expected_content:
                  raise Exception(f"{file_name}: content should be '{expected_content}' but got '{content}'")
        '';
    };
}
