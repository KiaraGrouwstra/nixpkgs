# Contracts module: routes requests from consumers to providers.
#
# This module does not depend on NixOS, so other module systems can import it.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    contractTypes = mkOption {
      description = ''
        Contract types that consumers and providers can use.

        Each contract type has an `interface`: a module with the options
        `request` and `response`.
        Consumers and providers import this module into their submodule types.
        To make the submodule type of a consumer, use `mkContract`.
      '';
      default = { };
      type = types.attrsOf lib.contract.definitionType;
    };

    contracts = mkOption {
      description = ''
        Contract instances, one attribute set for each contract type
        in [](#opt-contractTypes).
      '';
      default = { };
      type = types.submodule {
        options = lib.mapAttrs (
          contractName: contractType:
          mkOption {
            description = "Instances of the contract type `${contractName}`.";
            default = { };
            type = types.submodule (
              { config, ... }:
              let
                entryType = types.submodule { imports = [ contractType.consumerInterface ]; };
                # The `request` of an entry, without the aliases from `requestAliases`.
                request = want: lib.getAttrs contractType.requestOptionNames want.request;
                # An entry has only the keys of the interface, such as `request`.
                # Other attribute sets are namespaces, for example `want.<consumer>`.
                isEntry = v: v != { } && lib.isNestedAttrsLeaf lib.all entryType v;
                # Apply `f path entry` to each entry in `want`.
                # Remove empty namespaces, for example from `mkIf false`,
                # because a provider reads `{ }` as an entry.
                mapEntries =
                  f:
                  let
                    go =
                      path:
                      lib.concatMapAttrs (
                        name: v:
                        let
                          path' = path ++ [ name ];
                          mapped = go path' v;
                        in
                        if isEntry v then
                          { ${name} = f path' v; }
                        else
                          lib.optionalAttrs (mapped != { }) { ${name} = mapped; }
                      );
                  in
                  go [ ] config.want;
              in
              {
                options = {
                  want = mkOption {
                    description = ''
                      Requests from consumers.
                      Entries can be in nested attribute sets of any depth.
                      Each consumer puts its entries in an attribute set with its own name,
                      for example `want.<consumer>.<option>`.
                      An attribute set that contains only names of interface options,
                      such as `request`, is an entry and not a namespace.
                    '';
                    default = { };
                    type = types.nestedAttrsOf entryType;
                  };

                  requests = mkOption {
                    description = ''
                      The `request` of each entry in `want`, at the same path.
                      It does not have the aliases from `requestAliases`.
                    '';
                    readOnly = true;
                    type = types.attrsOf types.raw;
                    default = mapEntries (_: want: { request = request want; });
                    defaultText = lib.literalMD "the `request` of each entry in `want`";
                  };

                  providers = mkOption {
                    description = ''
                      Providers of this contract type.
                      Each provider is an attribute set with an entry
                      that has a `response` for each request that the provider gets
                      from `providerRequests.<provider>`, at the same path.
                    '';
                    default = { };
                    # Lazy, so that a provider can read its own `providerRequests` entry.
                    type = types.lazyAttrsOf types.raw;
                  };

                  defaultProvider = mkOption {
                    description = "Name of the provider that gets the requests.";
                    default = null;
                    type = types.nullOr (types.enum (lib.attrNames config.providers));
                  };

                  providerRequests = mkOption {
                    description = ''
                      The requests that each provider must fulfill.
                      A provider reads `providerRequests.<provider>`,
                      and not `requests`.
                    '';
                    readOnly = true;
                    type = types.attrsOf (types.attrsOf types.raw);
                    default = lib.mapAttrs (
                      name: _: if name == config.defaultProvider then config.requests else { }
                    ) config.providers;
                    defaultText = lib.literalMD "`requests` for `defaultProvider`, `{ }` for the other providers";
                  };

                  results = mkOption {
                    description = ''
                      For each entry in `want`, at the same path,
                      the `request` of the entry and the `response` from the provider in one attribute set.
                      Thus a consumer reads a request value from the same place as the response.
                      The `request` does not have the aliases from `requestAliases`.
                      A `response` attribute takes precedence over a `request` attribute with the same name.
                    '';
                    readOnly = true;
                    type = types.attrsOf types.raw;
                    default = mapEntries (
                      path: want:
                      if config.defaultProvider == null then
                        throw "contracts.${contractName}.want.${lib.showAttrPath path}: no provider. Set `contracts.${contractName}.defaultProvider`."
                      else
                        request want // (lib.getAttrFromPath path config.providers.${config.defaultProvider}).response
                    );
                    defaultText = lib.literalMD "the `request` of each entry in `want`, with the `response` from `defaultProvider`";
                  };
                };
              }
            );
          }
        ) config.contractTypes;
      };
    };
  };
}
