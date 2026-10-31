# A contract instance in the request of another contract.
# The routing does not find the inner instance, see `contracts-nested-request-route.nix`.
{
  lib,
  config,
  options,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  inherit (config.contractTypes) database fileSecrets;
in
{
  imports = [ lib.contract.module ];

  options = {
    app.db = mkOption {
      default = { };
      type = database.mkContract {
        request.name.default = "appdb";
      };
    };

    databaseProvider = mkOption {
      type = database.mkProviderType {
        fulfill =
          { name, passwordFile }:
          {
            url = "postgresql:///${name}?passfile=${passwordFile.response.path}";
            passwordFileOwner = passwordFile.request.owner;
          };
      };
    };

    secretProvider = mkOption {
      type = fileSecrets.mkProviderType {
        fulfill = request: { path = "/run/secrets/${request.owner}"; };
      };
    };
  };

  config = {
    # `mkContract` and `mkProviderType` are read-only, so set only `meta` and `interface`.
    contractTypes.fileSecrets = { inherit (lib.contracts.fileSecrets) meta interface; };

    contractTypes.database = {
      meta = {
        description = "A database, with a password file.";
        maintainers = [ lib.maintainers.kiara ];
      };
      interface = {
        options.request = mkOption {
          type = types.submodule {
            options.name = mkOption { type = types.str; };
            # An instance of the contract `fileSecrets`.
            options.passwordFile = mkOption {
              default = { };
              type = top.contractTypes.fileSecrets.mkContract {
                request = {
                  owner.default = "postgres";
                  group.default = "postgres";
                };
              };
            };
          };
        };
        options.response = mkOption {
          type = types.submodule {
            options.url = mkOption { type = types.str; };
            options.passwordFileOwner = mkOption { type = types.str; };
          };
        };
      };
    };

    # The consumer routes the outer instance.
    contracts.database.want.app.db = { inherit (config.app.db) request; };
    app.db.response = config.contracts.database.results.app.db;

    databaseProvider = config.contracts.database.providerRequests.databaseProvider;
    contracts.database.providers.databaseProvider = {
      module = options.databaseProvider;
      contract = [ ];
    };
    contracts.database.defaultProvider = config.contracts.database.providers.databaseProvider;

    secretProvider = config.contracts.fileSecrets.providerRequests.secretProvider;
    contracts.fileSecrets.providers.secretProvider = {
      module = options.secretProvider;
      contract = [ ];
    };
    contracts.fileSecrets.defaultProvider = config.contracts.fileSecrets.providers.secretProvider;
  };
}
