{ lib, ... }:
{
  options.foo = lib.mkOption {
    default = { };
    type =
      lib.contract.mkContract
        {
          boo = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options.bar = lib.mkOption { type = lib.types.int; };
            };
          };
        }
        {
          boo.bar.default = "baz";
        };
  };
}
