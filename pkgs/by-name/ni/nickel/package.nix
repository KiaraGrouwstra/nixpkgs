{
  lib,
  boost,
  rustPlatform,
  fetchFromGitHub,
  python3,
  pkg-config,
  nix,
  nix-update-script,
  enableNixImport ? true,
}:

rustPlatform.buildRustPackage rec {
  pname = "nickel";
  version = "1.9.1";

  src = fetchFromGitHub {
    owner = "KiaraGrouwstra";
    repo = "nickel";
    # rev = "refs/tags/${version}";
    rev = "6cad1cf5b72ae8bde73a8fee5a40f30edc6e1a22";
    hash = "sha256-DnGPkAEe+i+GVAH/zGFZkw8l4P8kVpoND9ciMCMIBUk=";
  };

  cargoHash = "sha256-evEBT2vICFETqCLrF5iMgkWaZdRxA/M3fRGimyPmF70=";

  cargoBuildFlags = [
    "-p nickel-lang-cli"
    "-p nickel-lang-lsp"
  ];

  buildInputs = if enableNixImport then [
    nix
    boost
  ] else [ ];

  nativeBuildInputs = [
    python3
  ] ++ (if enableNixImport then [
    pkg-config
  ] else [ ]);

  buildFeatures = if enableNixImport then [ "nix-experimental" ] else [ ];

  outputs = [
    "out"
    "nls"
  ];

  # disabledTests = if enableNixImport then [
  #   "fetch_targets"
  # ] else [ ];
  doCheck = false;

  # This fixes the way comrak is defined as a dependency, without the sed the build fails:
  #
  # cargo metadata failure: error: Package `nickel-lang-core v0.10.0
  # (/build/source/core)` does not have feature `comrak`. It has an optional
  # dependency with that name, but that dependency uses the "dep:" syntax in
  # the features table, so it does not have an implicit feature with that name.
  preBuild = ''
    sed -i 's/dep:comrak/comrak/' core/Cargo.toml
  '';

  postInstall = ''
    mkdir -p $nls/bin
    mv $out/bin/nls $nls/bin/nls
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    homepage = "https://nickel-lang.org/";
    description = "Better configuration for less";
    longDescription = ''
      Nickel is the cheap configuration language.

      Its purpose is to automate the generation of static configuration files -
      think JSON, YAML, XML, or your favorite data representation language -
      that are then fed to another system. It is designed to have a simple,
      well-understood core: it is in essence JSON with functions.
    '';
    changelog = "https://github.com/tweag/nickel/blob/${version}/RELEASES.md";
    license = licenses.mit;
    maintainers = with maintainers; [
      felschr
      matthiasbeyer
    ];
    mainProgram = "nickel";
  };
}
