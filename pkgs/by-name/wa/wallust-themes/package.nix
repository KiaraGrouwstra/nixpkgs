{
  lib,
  fetchFromGitea,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "wallust-themes";
  version = "1.1.0";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "explosion-mental";
    repo = "wallust-themes";
    rev = "3dd4eef932e28a9819eaa82cd02ffec23e51ffda";
    hash = "sha256-bCzO1vdo+iWeOFXRt+xrwKd6raZPyMedOKML08FW2Dk=";
  };

  cargoLock.lockFile = ./Cargo.lock;
  cargoPatches = [
    ./add-Cargo.lock.patch
  ];

  cargoBuildFeatures = [
    "gogh"
  ];

  installPhase = ''
    mkdir -p $out/share
    # cp ./themes.json $out/share
    cp -r ./colorschemes $out/share
  '';

  meta = {
    description = "Collection of built in wallust themes";
    homepage = "https://codeberg.org/explosion-mental/wallust-themes";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      kiara
    ];
    downloadPage = "https://codeberg.org/explosion-mental/wallust-themes/releases/tag/${finalAttrs.version}";
  };
})
