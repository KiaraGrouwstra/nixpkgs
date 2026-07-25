# Test:
#   ./meta-maintainers/test.nix
{ lib, ... }:
{
  imports = [ lib.genericModules.meta-maintainers ];
}
