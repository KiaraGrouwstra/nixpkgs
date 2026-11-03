# Each entry of `contracts.<type>.instances` has a `request` and a `response`.
# The provider `one` adds `providerOptions.one.offset` to the requests that it gets.
# The provider `two` multiplies the requests that it gets by two.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  # The contract type `number`.
  number = {
    options.contracts.number = lib.contract.mkContractOption {
      name = "number";
      description = "A number.";
      interface.options =
        let
          intOption = mkOption {
            type = types.submodule {
              options.value = mkOption { type = types.int; };
            };
          };
        in
        {
          request = intOption;
          response = intOption;
        };
    };
  };

  # A provider of `number`, that sets the response of its entries.
  mkProvider =
    providerName: response:
    { config, ... }:
    let
      provider = config.contracts.number.providers.${providerName};
    in
    {
      options.contracts.number.instances = mkOption {
        type = types.nestedAttrsOf (
          types.submodule (
            { instancePath, config, ... }:
            {
              options.providerOptions.${providerName}.offset = mkOption {
                type = types.int;
                default = 1;
              };
              config.response = lib.mkIf (lib.hasAttrByPath instancePath provider.instances) (
                lib.mkOptionDefault { value = response config; }
              );
            }
          )
        );
      };
      config.contracts.number.providers.${providerName} = { };
    };
in
{
  imports = [
    number
    (mkProvider "one" (instance: instance.request.value + instance.providerOptions.one.offset))
    (mkProvider "two" (instance: instance.request.value * 2))
  ];

  options = {
    # A consumer in a different evaluation, with its own `contracts`.
    services.sub = mkOption {
      default = { };
      type = types.submodule {
        imports = [ number ];
        contracts.number.instances.x.request.value = 30;
      };
    };
  };

  config = {
    contracts.number = {
      defaultProvider = config.contracts.number.providers.one;
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
        # A different provider for this entry.
        f.request.value = 10;
        f.provider = config.contracts.number.providers.two;
        # The user connects the entry of the other evaluation.
        sub-x.request = config.services.sub.contracts.number.instances.x.request;
        # Entries in nested attribute sets.
        ns.g.request.value = 10;
        ns.h.i.request.value = 10;
        ns.h.i.provider = config.contracts.number.providers.two;
        # An empty namespace, and not an entry.
        ns.empty = { };
        # No entry.
        ns.j = lib.mkIf false { request.value = 10; };
      };
    };

    services.sub.contracts.number.instances.x.response =
      config.contracts.number.instances.sub-x.response;
  };
}
