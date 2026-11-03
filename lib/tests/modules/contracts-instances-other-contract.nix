# A provider of a different contract type is not a provider of `number`.
{ lib, config, ... }:
{
  options.contracts.letter = lib.contract.mkContractOption {
    name = "letter";
    description = "A letter.";
    interface = { };
  };
  config.contracts.letter.providers.one = { };
  config.contracts.number.instances.a.provider = config.contracts.letter.providers.one;
}
