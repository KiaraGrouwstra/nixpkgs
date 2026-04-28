# generateFiles contract provider.
#
# Reads generateFiles contract requests, delegates storage to a varsBackend
# provider, and runs generation scripts at boot via a systemd service.
# Also bridges generated files into the fileSecrets contract.
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.services.vars;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    submodule
    ;
  generateFilesContract = "generateFiles";
  varsBackendContract = "varsBackend";
  fileSecretsContract = "fileSecrets";
  inherit (contracts.${generateFilesContract}) mkProviderType;

  generateFilesType = (options.services.vars.type.getSubOptions [ ]).${generateFilesContract}.type;

  flatInstances = lib.concatMapNestedAttrs' generateFilesType (path: instance: {
    ${lib.concatStringsSep "_" path} = instance;
  }) cfg.${generateFilesContract};

  sortedInstances =
    let
      instanceList = lib.mapAttrsToList (name: instance: {
        inherit name instance;
      }) flatInstances;
    in
    (lib.toposort (a: b: builtins.elem a.name b.instance.request.dependencies) instanceList).result;

  backendFiles = name: config.contracts.${varsBackendContract}.results.vars.${name}.files;

  generate-vars = pkgs.writeShellApplication {
    name = "generate-vars";
    text = ''
      set -euo pipefail

      ${lib.concatMapStringsSep "\n" (
        { name, instance }:
        let
          req = instance.request;
          bFiles = backendFiles name;
        in
        ''
          echo "=== Generator: ${name} ==="

          all_files_missing=true
          all_files_present=true
          ${lib.concatMapStringsSep "\n" (fileName: ''
            if test -e ${lib.escapeShellArg bFiles.${fileName}.path}; then
              all_files_missing=false
            else
              all_files_present=false
            fi
          '') (lib.attrNames req.files)}

          if [ "$all_files_missing" = false ] && [ "$all_files_present" = false ]; then
            echo "Inconsistent state for generator: ${name}"
            exit 1
          fi

          if [ "$all_files_present" = true ]; then
            echo "All files for ${name} are present, skipping."
          else
            echo "Generating files for ${name}..."

            out=$(mktemp -d)
            trap 'rm -rf "$out"' EXIT
            export out

            in=$(mktemp -d)
            export in
            ${lib.concatMapStringsSep "\n" (
              dep:
              let
                depFiles = backendFiles dep;
                depFileNames = lib.attrNames (flatInstances.${dep}.request.files or { });
              in
              ''
                mkdir -p "$in"/${lib.escapeShellArg dep}
                ${lib.concatMapStringsSep "\n" (fileName: ''
                  cp ${
                    lib.escapeShellArg depFiles.${fileName}.path
                  } "$in"/${lib.escapeShellArg dep}/${lib.escapeShellArg fileName}
                '') depFileNames}
              ''
            ) req.dependencies}

            (
              unset PATH
              ${lib.optionalString (req.runtimeInputs != [ ]) ''
                PATH=${lib.makeBinPath req.runtimeInputs}
                export PATH
              ''}
              ${req.script}
            )

            ${lib.concatMapStringsSep "\n" (fileName: ''
              if ! test -e "$out"/${lib.escapeShellArg fileName}; then
                echo "Generator ${name} failed to produce ${fileName}"
                exit 1
              fi
            '') (lib.attrNames req.files)}

            ${lib.concatMapStringsSep "\n" (
              fileName:
              let
                file = req.files.${fileName};
              in
              ''
                mkdir -p "$(dirname ${lib.escapeShellArg bFiles.${fileName}.path})"
                mv "$out"/${lib.escapeShellArg fileName} ${lib.escapeShellArg bFiles.${fileName}.path}
                chown ${lib.escapeShellArg "${file.owner}:${file.group}"} ${
                  lib.escapeShellArg bFiles.${fileName}.path
                }
                chmod ${lib.escapeShellArg file.mode} ${lib.escapeShellArg bFiles.${fileName}.path}
              ''
            ) (lib.attrNames req.files)}

            rm -rf "$out" "$in"
            trap - EXIT
          fi
        ''
      ) sortedInstances}
    '';
  };
in
{
  options.services.vars = mkOption {
    description = ''
      Declarative file generation provider (vars).

      Reads generateFiles contract requests and generates files at boot using
      the configured varsBackend for storage.
    '';
    type = submodule {
      options.${generateFilesContract} = mkOption {
        description = "Instances of the generateFiles contract fulfilled by vars.";
        default = config.contracts.${generateFilesContract}.requests;
        defaultText = lib.literalExpression "config.contracts.${generateFilesContract}.requests";
        type = mkProviderType {
          fulfill' =
            { name, request }:
            {
              files = lib.mapAttrs (fileName: _: {
                path = (backendFiles name).${fileName}.path;
              }) request.files;
            };
        };
      };

      options.${fileSecretsContract} = mkOption {
        description = "fileSecrets contract bridge: each generated file becomes a fileSecret.";
        default.vars = lib.concatMapNestedAttrs' generateFilesType (
          path: instance:
          let
            name = lib.concatStringsSep "_" path;
            bFiles = backendFiles name;
          in
          lib.concatMapAttrs (fileName: fileCfg: {
            ${lib.concatStringsSep "_" (path ++ [ fileName ])} = {
              request = {
                inherit (fileCfg) owner group mode;
              };
              result = {
                path = bFiles.${fileName}.path;
              };
            };
          }) instance.request.files
        ) cfg.${generateFilesContract};
        defaultText = lib.literalExpression "<computed from generateFiles requests + varsBackend results>";
        type = contracts.${fileSecretsContract}.mkProviderType { };
      };
    };
  };

  config = {
    contracts.${generateFilesContract}.providers.vars.module = options.services.vars;

    contracts.${varsBackendContract}.want.vars = lib.mapAttrs (_name: instance: {
      request.files = instance.request.files;
    }) flatInstances;

    systemd.services.generate-vars = lib.mkIf (flatInstances != { }) {
      description = "Generate vars files";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${generate-vars}/bin/generate-vars";
      };
    };

    environment.systemPackages = lib.mkIf (flatInstances != { }) [ generate-vars ];

    contracts.${fileSecretsContract} = {
      providers.vars = {
        module = options.services.vars;
        contract = [ fileSecretsContract ];
      };

      # Drive `results` from the bridge: each generated file becomes a
      # fileSecrets want entry under `vars.<instance>_<fileName>`, requesting
      # only ownership (the path is supplied by the bridge itself).
      want.vars = lib.concatMapNestedAttrs' generateFilesType (
        path: instance:
        lib.concatMapAttrs (fileName: fileCfg: {
          ${lib.concatStringsSep "_" (path ++ [ fileName ])}.request = {
            inherit (fileCfg) owner group mode;
          };
        }) instance.request.files
      ) cfg.${generateFilesContract};
    };
  };
}
