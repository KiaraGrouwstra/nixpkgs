{ lib, ... }:
let
  inherit (lib) mkOption modules types;
  inherit (types)
    attrs
    attrsOf
    listOf
    option
    submodule
    str
    ;
  # used to type-check contracts defined in `lib/contracts`.
  # type extracted from `contractTypes` to prevent dependency on `config`.
  # for human-oriented documentation, see `contractTypes` defined at `nixos/modules/contracts/default.nix`.
  contractModule = mkOption {
    type = submodule {
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
              input = mkOption {
                type = attrsOf option;
                apply = modules.mkContract;
              };
              output = mkOption {
                type = attrsOf option;
                apply = modules.mkContract;
              };
            };
          };
        };
        behaviorTest = mkOption {
          type = types.functionTo types.attrs;
          default = {
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
    };
  };
in
# yields: attrsOf contractModule
lib.mapAttrs (_: path: modules.evalOption contractModule (import path { inherit lib; })) {
  fileSecrets = ./file-secrets.nix;
}
