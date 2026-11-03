# Each entry of `contracts.<type>.instances` has a `request` and a `response`.
# The provider `one` adds `providerOptions.one.offset` to the requests that it gets.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  intOption = mkOption {
    type = types.submodule {
      options.value = mkOption { type = types.int; };
    };
  };
  number = {
    meta = {
      description = "A number.";
      maintainers = [ lib.maintainers.kiara ];
    };
    interface.options = {
      request = intOption;
      response = intOption;
    };
  };
in
{
  imports = [ lib.contract.module ];

  options = {
    # The provider `one` adds its name to the types of `provider` and `defaultProvider`,
    # and sets the `response` of each entry with its name in `provider`.
    contracts.number.defaultProvider = mkOption {
      type = types.nullOr (types.enum [ "one" ]);
    };
    contracts.number.instances = mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, ... }:
          {
            options.provider = mkOption {
              type = types.nullOr (types.enum [ "one" ]);
            };
            options.providerOptions.one.offset = mkOption {
              type = types.int;
              default = 1;
            };
            config.response = lib.mkIf (config.provider == "one") (
              lib.mkOptionDefault {
                value = config.request.value + config.providerOptions.one.offset;
              }
            );
          }
        )
      );
    };

    # A consumer in a different evaluation, with its own `contracts`.
    services.sub = mkOption {
      default = { };
      type = types.submodule {
        imports = [ lib.contract.module ];
        contractTypes = { inherit number; };
        contracts.number.instances.x.request.value = 30;
      };
    };
  };

  config = {
    contractTypes = { inherit number; };

    contracts.number = {
      defaultProvider = "one";
      instances = {
        # The response comes from `defaultProvider`.
        a.request.value = 10;
        # A definition of the user replaces the response of the provider.
        b.request.value = 10;
        b.response.value = 5;
        # No provider: the user connects the entry.
        c.request.value = 10;
        c.provider = null;
        c.response.value = 7;
        # No provider, and no response.
        d.request.value = 10;
        d.provider = null;
        # An option of the provider for this entry.
        e.request.value = 10;
        e.providerOptions.one.offset = 5;
        # The user connects the entry of the other evaluation.
        sub-x.request = config.services.sub.contracts.number.instances.x.request;
      };
    };

    services.sub.contracts.number.instances.x.response =
      config.contracts.number.instances.sub-x.response;
  };
}
