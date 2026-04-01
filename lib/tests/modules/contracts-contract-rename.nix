# Tests that using a renamed contract name emits a deprecation warning in config.warnings.
#
# mkRenamedOptionModule cannot be used for contracts.<name> because `contracts` is a single
# submodule-typed option — doRename cannot find or declare sub-options within it.
# Instead, a rename is implemented as a NixOS module that:
#   1. Defines the old contractType independently (same interface, separate declaration)
#   2. Adds a config.warnings entry when the old contract's `want` is non-empty
#
# Also tests the combination of a contract rename with an option rename inside that contract
# (extraImports.request), verifying that the requests filter excludes alias options from
# provider data even when both rename layers are active.
{ lib, config, ... }:
let
  sharedInterface = {
    request.value = lib.mkOption { type = lib.types.int; };
    result.value  = lib.mkOption { type = lib.types.int; };
  };
in
{
  imports = [
    ../../../nixos/modules/contracts/default.nix
    # Rename warning: emits config.warnings when contracts.oldName is used.
    ({ config, lib, ... }: {
      warnings =
        lib.optional (config.contracts.oldName.want != { })
          "The contract `oldName` has been renamed to `newName`. Please update your configuration."
        ++ lib.optional (config.contracts.oldNameWithRename.want != { })
          "The contract `oldNameWithRename` has been renamed to `newName`. Please update your configuration.";
    })
  ];

  # meta is a NixOS-level option; provide a stub so the contracts module's
  # `meta.buildDocsInSandbox = false` is accepted in this bare evalModules context.
  options.meta = lib.mkOption {
    type = lib.types.attrs;
    default = { };
  };
  options.warnings = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  options.result = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  config = {
    contractTypes.newName = {
      meta = { description = "New contract name (test)."; maintainers = [ ]; };
      interface = sharedInterface;
    };

    # Old contract type: same interface, declared independently to avoid self-reference.
    # (contractTypes.oldName = config.contractTypes.newName would cause infinite recursion
    # because config.contractTypes is built from all contractTypes definitions including oldName.)
    contractTypes.oldName = {
      meta = { description = "Deprecated: renamed to newName."; maintainers = [ ]; };
      interface = sharedInterface;
    };

    # Old contract type that also carries an option-level rename shim.
    # Tests the combination: deprecated contract name + deprecated request option name.
    contractTypes.oldNameWithRename = {
      meta = { description = "Deprecated: renamed to newName. Also renames request option."; maintainers = [ ]; };
      interface = sharedInterface // {
        extraImports.request = [
          (
            { config, options, ... }:
            {
              options.legacyValue = lib.mkOption {
                description = "Deprecated alias for value.";
                type = lib.types.int;
                visible = false;
                apply = lib.warn "The option `request.legacyValue` has been renamed to `request.value`. Please update your configuration.";
              };
              config = lib.mkIf options.legacyValue.isDefined {
                value = lib.mkDefault config.legacyValue;
              };
            }
          )
        ];
      };
    };

    # Scenario 1: consumer uses only the old contract name (canonical option name).
    contracts.oldName.want.consumer.instance.request.value = 5;
    contracts.oldName.defaultProvider =
      lib.mapAttrs (_consumer: lib.mapAttrs (_instance: v: {
        inherit (v) request;
        result.value = v.request.value + 1;
      })) config.contracts.oldName.requests;

    # Scenario 2: consumer uses both the old contract name and the old option name.
    contracts.oldNameWithRename.want.consumer.instance.request.legacyValue = 5;
    contracts.oldNameWithRename.defaultProvider =
      lib.mapAttrs (_consumer: lib.mapAttrs (_instance: v: {
        inherit (v) request;
        result.value = v.request.value + 1;
      })) config.contracts.oldNameWithRename.requests;

    result = lib.concatStringsSep "%" config.warnings;
  };
}
