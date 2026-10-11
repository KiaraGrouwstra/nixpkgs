# A consumer sets a renamed `request` option by its old name.
# The provider gets only the new name.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.contracts) number;
  intOption = mkOption {
    type = types.submodule {
      options.value = mkOption { type = types.int; };
    };
  };
in
{
  imports = [ lib.contract.module ];

  options = {
    consumer = mkOption {
      default = {
        request.oldValue = 7;
      };
      type = config.contractTypes.number.mkContract { };
    };

    providerRequestNames = mkOption {
      type = types.str;
      default = lib.concatStringsSep "," (lib.attrNames number.providerRequests.increment.app.x.request);
    };

    resultNames = mkOption {
      type = types.str;
      default = lib.concatStringsSep "," (lib.attrNames number.results.app.x);
    };
  };

  config = {
    contractTypes.number = {
      meta = {
        description = "A number.";
        maintainers = [ ];
      };
      interface.options = {
        request = intOption;
        response = intOption;
      };
      requestAliases = [
        (
          { config, options, ... }:
          {
            options.oldValue = mkOption {
              description = "Alias of `value`.";
              type = types.int;
              visible = false;
              apply = lib.warn "The option `request.oldValue` of the contract type `number` is renamed to `request.value`.";
            };
            config = lib.mkIf options.oldValue.isDefined {
              value = lib.mkDefault config.oldValue;
            };
          }
        )
      ];
    };

    contracts.number = {
      want.app.x.request.oldValue = 5;
      providers.increment.app.x.response.value =
        number.providerRequests.increment.app.x.request.value + 1;
      defaultProvider = "increment";
    };
  };
}
