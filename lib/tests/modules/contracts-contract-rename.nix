# Tests that using a renamed contract name emits a deprecation warning in config.warnings.
#
# mkRenamedOptionModule cannot be used for contracts.<name> because `contracts` is a single
# submodule-typed option — doRename cannot find or declare sub-options within it.
# Instead, a rename is implemented as a NixOS module that:
#   1. Defines the old contractType independently (same interface, separate declaration)
#   2. Adds a config.warnings entry when the old contract's `want` is non-empty
{ lib, config, ... }:
let
  sharedInterface = {
    request.value = lib.mkOption { type = lib.types.int; };
    result.value = lib.mkOption { type = lib.types.int; };
  };
in
{
  imports = [
    ../../contracts/module.nix
    # Rename warning: emits config.warnings when contracts.oldName is used.
    (
      { config, lib, ... }:
      {
        warnings = lib.optional (
          config.contracts.oldName.want != { }
        ) "The contract `oldName` has been renamed to `newName`. Please update your configuration.";
      }
    )
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
      meta = {
        description = "New contract name (test).";
        maintainers = [ ];
      };
      interface = sharedInterface;
    };
    # Old contract type: same interface, declared independently to avoid self-reference.
    # (contractTypes.oldName = config.contractTypes.newName would cause infinite recursion
    # because config.contractTypes is built from all contractTypes definitions including oldName.)
    contractTypes.oldName = {
      meta = {
        description = "Deprecated: renamed to newName.";
        maintainers = [ ];
      };
      interface = sharedInterface;
    };

    # Consumer uses the old (renamed) contract name.
    contracts.oldName.want.consumer.instance.request.value = 5;

    # Provider wired to the old contract, incrementing the request value by 1.
    contracts.oldName.defaultProvider = lib.mapAttrs (
      _consumer:
      lib.mapAttrs (
        _instance: v: {
          inherit (v) request;
          result.value = v.request.value + 1;
        }
      )
    ) config.contracts.oldName.requests;

    result = lib.concatStringsSep "%" config.warnings;
  };
}
