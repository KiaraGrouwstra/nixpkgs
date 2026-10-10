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
      '';
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            meta = mkOption {
              description = "Information about the contract type and its maintenance.";
              type = types.submodule {
                options = {
                  description = mkOption {
                    description = "What the contract type is for.";
                    type = types.str;
                  };
                  maintainers = mkOption {
                    description = "Maintainers of the contract type.";
                    type = types.listOf types.attrs;
                  };
                };
              };
            };
            interface = mkOption {
              description = "Module with the options `request` and `response`.";
              type = types.deferredModule;
            };
          };
        }
      );
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
              {
                options = {
                  want = mkOption {
                    description = ''
                      Requests from consumers.
                      Each name must be unique for all consumers,
                      for example `<consumer>-<option>`.
                    '';
                    default = { };
                    type = types.attrsOf (types.submodule { imports = [ contractType.interface ]; });
                  };

                  requests = mkOption {
                    description = "The `request` of each entry in `want`.";
                    readOnly = true;
                    type = types.attrsOf types.raw;
                    default = lib.mapAttrs (_: want: { inherit (want) request; }) config.want;
                    defaultText = lib.literalMD "the `request` of each entry in `want`";
                  };

                  providers = mkOption {
                    description = ''
                      Providers of this contract type.
                      Each provider is an attribute set with an entry
                      that has a `response` for each request that the provider gets
                      from `providerRequests.<provider>`.
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
                    description = "The `response` from the provider for each entry in `want`.";
                    readOnly = true;
                    type = types.attrsOf types.raw;
                    default = lib.mapAttrs (
                      name: _:
                      if config.defaultProvider == null then
                        throw "contracts.${contractName}.want.${name}: no provider. Set `contracts.${contractName}.defaultProvider`."
                      else
                        config.providers.${config.defaultProvider}.${name}.response
                    ) config.want;
                    defaultText = lib.literalMD "the `response` from `defaultProvider` for each entry in `want`";
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
