# Tests that contract requests support submodule-typed options.
#
# Defines a contract whose request has a `connection` submodule (with `host`
# and `port` sub-options) alongside a flat `name` option.  The provider reads
# both and produces a result string, verifying the full structure survives the
# want -> requests -> provider -> results round-trip.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;

  connectionContractDef = {
    meta = {
      description = "Contract with a submodule-typed request for testing.";
      maintainers = [ ];
    };
    interface = {
      request = {
        name = mkOption {
          description = "Service name.";
          type = types.str;
        };
        connection = mkOption {
          description = "Connection parameters.";
          type = types.submodule {
            options = {
              host = mkOption {
                description = "Hostname.";
                type = types.str;
              };
              port = mkOption {
                description = "Port number.";
                type = types.int;
              };
            };
          };
        };
      };
      result.url = mkOption {
        description = "Constructed URL.";
        type = types.str;
      };
    };
  };

  evaluated = lib.evalOption (mkOption { type = lib.contract.templateType; }) connectionContractDef;
  inherit (evaluated) extend;
in
{
  imports = [ ../../contracts/module.nix ];

  options.meta = mkOption {
    type = types.attrs;
    default = { };
  };

  options.services.urlbuilder.connection = mkOption {
    type = types.nestedAttrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            request = mkOption { type = extend.request { }; };
            result = mkOption { type = extend.result { }; };
          };
          config.result.url = lib.mkDefault
            "${config.request.name}://${config.request.connection.host}:${toString config.request.connection.port}";
        }
      )
    );
  };

  config = {
    contractTypes.connection = connectionContractDef;

    contracts.connection.want.myapp.db = {
      request = {
        name = "postgresql";
        connection = {
          host = "db.example.com";
          port = 5432;
        };
      };
    };

    services.urlbuilder.connection = config.contracts.connection.requests;
    contracts.connection.providers.urlbuilder = config.services.urlbuilder.connection;
    contracts.connection.defaultProviderName = "urlbuilder";
  };
}
