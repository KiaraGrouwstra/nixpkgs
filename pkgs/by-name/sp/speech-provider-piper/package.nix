{
  lib,
  stdenv,
  fetchFromGitHub,
  cargo,
  meson,
  ninja,
  pkg-config,
  rustPlatform,
  rustc,
  espeak-ng,
  glib,
  onnxruntime,
  libspeechprovider,
  sonic,
  darwin,
  # Override the compiled-in voices directory. Useful for NixOS where voices
  # are installed into the system profile via environment.systemPackages.
  voicesDir ? null,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "speech-provider-piper";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "project-spiel";
    repo = "speech-provider-piper";
    rev = "SPEECH_PROVIDER_PIPER_${lib.replaceStrings [ "." ] [ "_" ] finalAttrs.version}";
    hash = "sha256-vkKZ75yJeoAditIFZ0RvsCF/chDYzJwqC4WpdZTHEyM=";
  };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "audio-ops-1.0.0" = "sha256-P27R4S3HwI1FJJsSLc0q+j082MTpVmNrf8JuAhPsUxo=";
      "glib-sys-0.20.0" = "sha256-hfqCIOhyxkeDFT4BJL+1kI2DZSFOjZWuCtc8HHyn4vE=";
      "speechprovider-0.1.0" = "sha256-Z+Fzec5uE87SfHCt5h/Hnts2RJ08twgm13HDvgLRiZ0=";
    };
  };

  nativeBuildInputs = [
    cargo
    meson
    ninja
    pkg-config
    rustPlatform.bindgenHook
    rustPlatform.cargoSetupHook
    rustc
  ];

  buildInputs =
    [
      espeak-ng
      glib
      libspeechprovider
      onnxruntime
      sonic
    ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
    ];

  strictDeps = true;

  # Patch espeak-phonemizer (from the sonata workspace) to use stable Rust.
  # ptr_sub_ptr and str_lines_remainder are nightly-only in the bundled version.
  postPatch = ''
    # Remove nightly Rust features from espeak-phonemizer (ptr_sub_ptr, str_lines_remainder)
    patch -d "$cargoDepsCopy" -p1 < ${./espeak-phonemizer-stable.patch}
    # Fix const/mut mismatch with system sonic (sonicWriteFloatToStream takes float* not const float*)
    patch -d "$cargoDepsCopy" -p1 < ${./sonata-synth-const.patch}
  '';

  mesonFlags = [
    "-Doffline=true"
  ] ++ lib.optional (voicesDir != null) "-Dvoices_dir=${voicesDir}";

  env = {
    ORT_STRATEGY = "system";
    ORT_LIB_LOCATION = "${onnxruntime}/lib";
    ORT_PREFER_DYNAMIC_LINK = "1";
    OPENSSL_NO_VENDOR = "1";
    SYSTEM_SONIC_PREFIX = "${sonic}";
    USE_SYSTEM_ESPEAK = "1";
  };

  meta = {
    description = "Spiel speech provider for neural TTS models like Piper";
    homepage = "https://github.com/project-spiel/speech-provider-piper";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ jtojnar ];
    mainProgram = "speech-provider-piper";
    platforms = lib.platforms.unix;
  };
})
