{ lib, ... }:
let
  inherit (lib) mkOption;
  inherit (lib.types)
    attrs
    attrsOf
    functionTo
    submodule
    listOf
    str
    optionType
    ;
in
{
  options.contracts = mkOption {
    description = ''
      Base option for a contract.

      To create a new contract, add an instance of `config.contracts.<name>`
      and define the `meta`, `input` and `output` options.
      The `consumer` and `provider` options will then be set up automatically
      and contain respectively the type of a consumer and provider
      of this new contract.

      To use the `<name>` contract, declare an option with either the
      `config.contracts.<name>.consumer` or `config.contracts.<name>.provider`
      type.

      The `behaviorTest` option is used to ensure all `provider` of a contract
      behave the same way.
    '';
    type = attrsOf (
      submodule (instance: {
        options = {
          meta = mkOption {
            description = ''
              Useful information about the contract and its maintenance.
            '';
            type = submodule {
              options = {
                maintainers = mkOption {
                  description = ''
                    Maintainers of the contract.
                  '';
                  type = listOf str;
                };
                description = mkOption {
                  description = ''
                    Description of the contract.
                  '';
                  type = str;
                };
              };
            };
          };
          interface = mkOption {
            default = { };
            type = submodule {
              options = {
                input = mkOption {
                  description = ''
                    Input type of a contract.
                  '';
                  type = optionType;
                };
                output = mkOption {
                  description = ''
                    Output type of a contract.
                  '';
                  type = optionType;
                };
              };
            };
          };
          consumer = mkOption {
            description = ''
              Consumer type for a contract.
              This option is set up automatically.
              Define instead the `input` and `output` options.
            '';
            type = optionType;
            default = submodule {
              options = {
                input = mkOption {
                  type = instance.config.interface.input;
                };
                output = mkOption {
                  type = instance.config.interface.output;
                };
              };
            };
          };
          requests = mkOption {
            # type = listOf ?;
            default = [ ];
          };
          behaviorTest = mkOption {
            # The type should be more precise of course.
            # There should actually be a NixOSTest type.
            # And we can probably do something fancy with the `input` and `output` modules.
            type = functionTo attrs;
          };
        };
      })
    );
  };
}
