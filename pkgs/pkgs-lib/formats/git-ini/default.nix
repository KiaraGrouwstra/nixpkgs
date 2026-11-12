{
  pkgs,
  lib,
}:
let
  common = (import ../ini/default.nix { inherit pkgs lib; }).common;
  inherit (common)
    iniAtom
    ;

  inherit (lib.generators)
    toGitINI
    ;
  inherit (lib.types)
    attrsOf
    either
    ;
in
{
  format =
    {
      listsAsDuplicateKeys ? false,
      ...
    }:
    let
      atom = iniAtom {
        inherit listsAsDuplicateKeys;
        listToValue = null;
        atomsCoercedToLists = false;
      };
    in
    lib.fix (self: {
      type = attrsOf (attrsOf (either atom (attrsOf atom)));
      lib.types.atom = atom;
      generateText = toGitINI;
      generate = name: value: pkgs.writeText name (self.generateText value);
    });
}
