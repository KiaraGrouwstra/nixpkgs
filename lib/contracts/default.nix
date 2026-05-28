{ lib, ... }:
let
  callLibs = file: import file { inherit lib; };
in
{
  module = ./module.nix;
  definitionType = callLibs ./definition-type.nix;
}
