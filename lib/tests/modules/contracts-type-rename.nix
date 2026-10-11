# The contract type `number` is renamed to `count`.
# A consumer of `number` still works, and the provider of `count` fulfills its request.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.contracts) count;
  intOption = mkOption {
    type = types.submodule {
      options.value = mkOption { type = types.int; };
    };
  };

  # The module that renames `number` to `count`.
  rename =
    { config, ... }:
    let
      inherit (config.contracts) count number;
    in
    {
      contractTypes.number = {
        meta = {
          description = "Deprecated: renamed to `count`.";
          maintainers = [ ];
        };
        inherit (config.contractTypes.count) interface requestAliases;
      };

      # Send the requests of `number` to `count`, and the responses back.
      contracts.count.want = number.requests;
      contracts.number = lib.mkIf (count.defaultProvider != null) {
        providers.count = count.providers.${count.defaultProvider};
        defaultProvider = "count";
      };

      warnings = lib.optional (number.want != { }) "The contract type `number` is renamed to `count`.";
    };
in
{
  imports = [
    lib.contract.module
    rename
  ];

  options = {
    # NixOS declares this option.
    warnings = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    services.increment = mkOption {
      default = count.providerRequests.increment;
      type = config.contractTypes.count.mkProviderType {
        fulfill =
          { value }:
          {
            value = value + 1;
          };
      };
    };

    wantedNames = mkOption {
      type = types.str;
      default = lib.concatStringsSep "," (lib.attrNames count.want);
    };
  };

  config = {
    contractTypes.count = {
      meta = {
        description = "A number.";
        maintainers = [ ];
      };
      interface.options = {
        request = intOption;
        response = intOption;
      };
    };

    # A consumer of the old name, and a consumer of the new name.
    contracts.number.want.old.x.request.value = 5;
    contracts.count.want.new.x.request.value = 1;

    contracts.count.providers.increment = config.services.increment;
    contracts.count.defaultProvider = "increment";
  };
}
