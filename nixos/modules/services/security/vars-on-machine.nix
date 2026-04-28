# On-machine varsBackend provider.
#
# Stores generated files directly on the filesystem at a configurable location.
# Files are organized as: {fileLocation}/{secret,public}/{instance}/{file}
{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.services.vars-on-machine;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "varsBackend";
  providerName = "on-machine";
  inherit (config.contracts.${contract}) mkProviderType;
in
{
  # The contract provider option reads `config.contracts` for its
  # `type`/`default`, which cannot be evaluated in the sandboxed split options
  # doc build. Document it in the eager build instead.
  meta.buildDocsInSandbox = false;

  options.services.vars-on-machine = mkOption {
    description = ''
      On-machine storage backend for vars.
      Stores generated files directly on the filesystem.
    '';
    type = submodule (vars-on-machine: {
      options = {
        fileLocation = mkOption {
          description = "Base directory for storing generated files.";
          type = str;
          default = "/var/lib/vars";
        };

        ${contract} = mkOption {
          description = "Instances of the varsBackend contract.";
          default = config.contracts.${contract}.providerRequests.${providerName};
          defaultText = lib.literalExpression "config.contracts.${contract}.providerRequests.${providerName}";
          type = mkProviderType {
            fulfill' =
              { name, request, ... }:
              {
                files = lib.mapAttrs (
                  fileName: fileCfg:
                  let
                    subdir = if fileCfg.secret then "secret" else "public";
                  in
                  {
                    path = "${vars-on-machine.config.fileLocation}/${subdir}/${name}/${fileName}";
                  }
                ) request.files;
              };
          };
        };
      };
    });
  };

  config = {
    contracts.${contract}.providers.on-machine.module = options.services.vars-on-machine;
  };
}
