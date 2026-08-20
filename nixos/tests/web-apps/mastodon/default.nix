{
  system ? builtins.currentSystem,
  pkgs,
  handleTestOn,
  runTestOn,
  ...
}:
let
  supportedSystems = [
    "x86_64-linux"
    "i686-linux"
    "aarch64-linux"
  ];

in
{
  standard = handleTestOn supportedSystems ./standard.nix { inherit system pkgs; };
  remote-databases = handleTestOn supportedSystems ./remote-databases.nix { inherit system pkgs; };
  upgrade = runTestOn supportedSystems ./upgrade.nix;
}
