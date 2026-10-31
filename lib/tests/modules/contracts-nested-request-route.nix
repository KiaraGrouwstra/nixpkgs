# The consumer routes the inner instance with its own `want` entry.
{ config, ... }:
{
  contracts.fileSecrets.want.app.dbPassword = {
    inherit (config.app.db.request.passwordFile) request;
  };
  app.db.request.passwordFile.response = config.contracts.fileSecrets.results.app.dbPassword;
}
