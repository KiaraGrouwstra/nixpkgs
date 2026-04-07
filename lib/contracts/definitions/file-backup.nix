{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    listOf
    nonEmptyListOf
    package
    path
    str
    submodule
    ;
in
{
  meta = {
    description = ''
      Contract for file backup where a directory containing
      regular files is to be backed up.
    '';
    maintainers = with lib.maintainers; [
      kiara
    ];
  };
  interface = {
    request = {
      user = mkOption {
        description = ''
          Unix user doing the backups.
        '';
        type = str;
        example = "vaultwarden";
      };

      sourceDirectories = mkOption {
        description = ''
          Directories to back up.
        '';
        type = nonEmptyListOf str;
        example = [ "/var/lib/vaultwarden" ];
      };

      excludePatterns = mkOption {
        description = ''
          File patterns to exclude.
        '';
        type = listOf str;
        default = [ ];
      };

      hooks = mkOption {
        description = ''
          Hooks to run around the backup.
        '';
        default = { };
        type = submodule {
          options = {
            beforeBackup = mkOption {
              description = ''
                Hooks to run before backup.
              '';
              type = listOf path;
              default = [ ];
            };

            afterBackup = mkOption {
              description = ''
                Hooks to run after backup.
              '';
              type = listOf path;
              default = [ ];
            };
          };
        };
      };
    };
    result = {
      script = mkOption {
        description = ''
          Script package exposing verbs:

          **`<script> backup`** — take a backup

          **`<script> snapshots`** — list snapshots, one id per line

          **`<script> restore <snap>`** — restore named snapshot

          **`<script> exec <args...>`** — passthrough to underlying tool
        '';
        type = package;
      };
    };
  };
  behaviorTest =
    {
      name,
      providerRoot,
      extraModules ? [ ],
    }:
    let
      contractWiringModule =
        { config, ... }:
        {
          test.result.script = (lib.getAttrFromPath providerRoot config).result.script;

          imports = extraModules ++ [
            (lib.setAttrByPath providerRoot {
              request = config.test.input;
            })
          ];
        };
    in
    {
      name = "contracts_filebackup_${name}";

      nodes.machine =
        { config, pkgs, ... }:
        {
          options = {
            test = {
              input = {
                user = mkOption {
                  type = str;
                };
                sourceDirectories = mkOption {
                  type = nonEmptyListOf str;
                };
                excludePatterns = mkOption {
                  type = listOf str;
                };
              };

              result = {
                script = mkOption {
                  type = package;
                };
                bin = mkOption {
                  type = str;
                  internal = true;
                  default = lib.getExe config.test.result.script;
                };
              };
            };

            jsonTestConfig = mkOption {
              type = types.path;
              default = pkgs.writeText "config.json" (builtins.toJSON config.test);
            };
          };

          config = {
            specialisation.root.configuration =
              { config, ... }:
              {
                imports = [ contractWiringModule ];

                test.input = {
                  user = "root";
                  sourceDirectories = [
                    "/opt/files/A"
                    "/opt/files/B"
                  ];
                  excludePatterns = [ "_exclude" ];
                };
              };

            specialisation.user.configuration =
              { config, ... }:
              {
                imports = [ contractWiringModule ];

                test.input = {
                  user = "me";
                  sourceDirectories = [
                    "/opt/files/A"
                    "/opt/files/B"
                  ];
                  excludePatterns = [ "_exclude" ];
                };
                users.users.${config.test.input.user} = {
                  isSystemUser = true;
                  group = config.test.input.user;
                  home = "/home/${config.test.input.user}";
                  createHome = true;
                };
                users.groups.${config.test.input.user} = { };
              };
          };
        };

      extraPythonPackages = p: [ p.dictdiffer ];

      testScript =
        { nodes, ... }:
        let
          specialisations = "${nodes.machine.system.build.toplevel}/specialisation";
        in
        ''
          from datetime import datetime, timedelta
          from dictdiffer import diff
          import json
          import re

          def list_files(dir):
              files_and_content = {}

              files = machine.succeed(f"""find {dir} -type f""").split("\n")[:-1]

              for f in files:
                  content = machine.succeed(f"""cat {f}""").strip()
                  files_and_content[f] = content

              return files_and_content

          def assert_files(dir, files):
              result = list(diff(list_files(dir), files))
              if len(result) > 0:
                  raise Exception("Unexpected files:", result)

          def run_test_with_config(file):
              config = json.loads(machine.succeed(f"cat {file}"))
              script = config["result"]["bin"]
              user = config["input"]["user"]
              sourceDirectories = config["input"]["sourceDirectories"]

              with subtest("Create initial content"):
                  for path in sourceDirectories:
                      machine.succeed(f"""
                          mkdir -p {path}
                          echo repo_fileA_1 > {path}/fileA
                          echo repo_fileB_1 > {path}/fileB
                          touch {path}/_exclude

                          chown {user}: -R {path}
                          chmod go-rwx -R {path}
                      """)

                  for path in sourceDirectories:
                      assert_files(path, {
                          f'{path}/fileA': 'repo_fileA_1',
                          f'{path}/fileB': 'repo_fileB_1',
                          f'{path}/_exclude': "",
                      })

              with subtest("First backup in repo"):
                  machine.succeed(f"{script} backup")

              with subtest("One snapshot"):
                  out = machine.succeed(f"{script} snapshots").splitlines()
                  print(f"Found snapshots:\n{out}")
                  if len(out) != 1:
                      raise Exception(f"Unexpected snapshots:\n{out}")

              # To accommodate for snapshot orchestrators which keep only a given amount
              # of snapshots per unit of time, we set the time to now + 2h.
              new_date = (datetime.now() + timedelta(hours=2)).strftime("%Y-%m-%d %H:%M:%S")
              machine.succeed(f"timedatectl set-time '{new_date}'")

              with subtest("New content"):
                  for path in sourceDirectories:
                      machine.succeed(f"""
                          echo repo_fileA_2 > {path}/fileA
                          echo repo_fileB_2 > {path}/fileB
                          """)

                      assert_files(path, {
                          f'{path}/fileA': 'repo_fileA_2',
                          f'{path}/fileB': 'repo_fileB_2',
                          f'{path}/_exclude': "",
                      })

              with subtest("Second backup in repo"):
                  machine.succeed(f"{script} backup")

              with subtest("Two snapshots"):
                  out = machine.succeed(f"{script} snapshots").splitlines()
                  print("Found snapshots:")
                  for i, s in enumerate(out):
                      print(f" {i+1}: {s}")
                  if len(out) != 2:
                      raise Exception(f"Unexpected snapshots:\n{out}")

              firstSnapshot = re.split("[ \t+]", out[0], maxsplit=1)[0]
              secondSnapshot = re.split("[ \t+]", out[1], maxsplit=1)[0]

              with subtest("Delete content"):
                  for path in sourceDirectories:
                      machine.succeed(f"""rm -r {path}/*""")

                      assert_files(path, {})

              with subtest("Restore second backup"):
                  machine.succeed(f"{script} restore {secondSnapshot}")

                  for path in sourceDirectories:
                      assert_files(path, {
                          f'{path}/fileA': 'repo_fileA_2',
                          f'{path}/fileB': 'repo_fileB_2',
                      })

              with subtest("Restore first backup"):
                  machine.succeed(f"{script} restore {firstSnapshot}")

                  for path in sourceDirectories:
                      assert_files(path, {
                          f'{path}/fileA': 'repo_fileA_1',
                          f'{path}/fileB': 'repo_fileB_1',
                      })

              machine.succeed("rm -r /opt")

          with subtest("Test 1 - user=root"):
              machine.succeed("${specialisations}/root/bin/switch-to-configuration test")
              run_test_with_config("${nodes.machine.specialisation.root.configuration.jsonTestConfig}")

          with subtest("Test 2 - user=me"):
              machine.succeed("${specialisations}/user/bin/switch-to-configuration test")
              run_test_with_config("${nodes.machine.specialisation.user.configuration.jsonTestConfig}")
        '';
    };
}
