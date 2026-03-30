{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrs
    functionTo
    listOf
    optionType
    submodule
    str
    ;
  # used to type-check contracts defined in `lib/contracts`.
  # type extracted from `contractTypes` to prevent dependency on `config`.
  # for human-oriented documentation, see `contractTypes` defined at `nixos/modules/contracts/default.nix`.
  contractModule = mkOption {
    type = submodule (contract: {
      options = {
        meta = mkOption {
          type = submodule {
            options = {
              description = mkOption {
                type = str;
              };
              maintainers = mkOption {
                type = listOf attrs;
              };
            };
          };
        };
        interface = mkOption {
          type = submodule {
            options = {
              request = mkOption {
                type = optionType;
              };
              result = mkOption {
                type = optionType;
              };
            };
          };
        };
        mkContract = mkOption {
          type = functionTo optionType;
          readOnly = true;
          default =
            overrides:
            lib.contract.extendSubmodule overrides (submodule {
              options = lib.mapAttrs (_: type: mkOption { inherit type; }) contract.config.interface;
            });
        };
        behaviorTest = mkOption {
          type = types.functionTo types.attrs;
          default =
            {
              name,
              extraModules ? [ ],
            }:
            {
              name = "contracts_<contract>_${name}";
              containers.machine =
                { ... }:
                {
                  imports = extraModules;
                };
              testScript =
                { ... }:
                ''
                  machine.succeed("echo 'please define a test!' >&2; exit 1")
                '';
            };
        };
      };
    });
  };
in
# yields: attrsOf contractModule
lib.mapAttrs (_: path: lib.contract.evalOption contractModule (import path { inherit lib; })) {
  fileSecrets = ./file-secrets.nix;
}
