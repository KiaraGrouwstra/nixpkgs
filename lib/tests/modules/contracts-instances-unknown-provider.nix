# A provider that is not in `providers` is an error.
{ config, ... }:
{
  contracts.number.instances.a.provider = config.contracts.number.providers.won;
}
