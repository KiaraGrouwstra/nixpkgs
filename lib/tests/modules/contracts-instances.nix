# Each entry of `contracts.<type>.instances` has a `request` and a `response`.
# The provider `one` adds 1 to the requests that it gets.
{
  lib,
  config,
  options,
  ...
}:
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
    services.one.number = mkOption {
      type = types.raw;
      default = lib.mapAttrs (_: entry: {
        response.value = entry.request.value + 1;
      }) config.contracts.number.providerRequests.one;
    };

    # A consumer in a different evaluation, with its own `contracts`.
    services.sub = mkOption {
      default = { };
      type = types.submodule {
        imports = [ lib.contract.module ];
        contractTypes = { inherit number; };
        contracts.number.instances.x.request.value = 30;
        contracts.number.instances.x.enable = true;
      };
    };
  };

  config = {
    contractTypes = { inherit number; };

    contracts.number = {
      providers.one.module = options.services.one;
      defaultProvider = config.contracts.number.providers.one;
      instances = {
        # The response comes from `defaultProvider`.
        a.enable = true;
        a.request.value = 10;
        # A definition of the user replaces the response of the provider.
        b.enable = true;
        b.request.value = 10;
        b.response.value = 5;
        # No provider: the user connects the entry.
        c.enable = true;
        c.request.value = 10;
        c.provider = null;
        c.response.value = 7;
        # No provider, and no response.
        d.enable = true;
        d.request.value = 10;
        d.provider = null;
        # Not enabled: the provider does not get the request.
        e.request.value = 10;
        # The user connects the entry of the other evaluation.
        sub-x.enable = true;
        sub-x.request = config.services.sub.contracts.number.instances.x.request;
      };
    };

    services.sub.contracts.number.instances.x.response =
      config.contracts.number.instances.sub-x.response;
  };
}
