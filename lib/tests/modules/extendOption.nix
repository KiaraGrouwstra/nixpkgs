{ lib, ... }:
{
  options.foo =
    lib.contract.extendOption
      {
        boo.bar.default = "baz";
      }
      (
        lib.mkOption {
          default = { };
          type = lib.types.submodule {
            options.boo = lib.mkOption {
              default = { };
              type = lib.types.submodule {
                options.bar = lib.mkOption { type = lib.types.int; };
              };
            };
          };
        }
      );
}
