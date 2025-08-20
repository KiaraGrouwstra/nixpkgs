{
  lib,
  fetchFromGitHub,
  python3,
  stdenv,
}:

stdenv.mkDerivation {
  name = "nixpkgs-staging-bisecter";

  src = fetchFromGitHub {
    owner = "symphorien";
    repo = "nixpkgs-staging-bisecter";
    rev = "657bec3c3e8cb2d7b32b876c7bd44044dabb9161";
    hash = "sha256-+e0CqoKeAG4dduj3I45I5BLdciq6l7PgCCLMi4FCCIA=";
  };

  buildInputs = [ python3 ];

  installPhase = ''
    mkdir -p $out/bin
    cp bisecter.py $out/bin/nixpkgs-staging-bisecter
  '';

  meta = {
    description = "minimize rebuilds when bisecting through mass rebuilds";
    homepage = "https://github.com/symphorien/nixpkgs-staging-bisecter";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ kiara ];
    platforms = lib.platforms.linux;
    mainProgram = "nixpkgs-staging-bisecter";
  };
}
