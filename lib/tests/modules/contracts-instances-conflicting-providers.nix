# Two different providers in `defaultProvider` conflict.
{ config, ... }:
{
  contracts.number.defaultProvider = config.contracts.number.providers.two;
}
