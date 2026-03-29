{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  python3,
  gobject-introspection,
  gi-docgen,
  glib,
  gst_all_1,
  libspeechprovider,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libspiel";
  version = "1.0.4";

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "project-spiel";
    repo = "libspiel";
    rev = "SPIEL_${lib.replaceStrings [ "." ] [ "_" ] finalAttrs.version}";
    hash = "sha256-onGSWeIruQb+ySTbUlzWv6jgKn+DBMn/mJark3xS3s0=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    python3
    gobject-introspection
    gi-docgen
  ];

  buildInputs = [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    libspeechprovider
  ];

  propagatedBuildInputs = [
    glib
  ];

  strictDeps = true;

  meta = {
    description = "Speech synthesis client library";
    homepage = "https://github.com/project-spiel/libspiel";
    license = lib.licenses.lgpl21Only;
    maintainers = with lib.maintainers; [ kiara ];
    mainProgram = "spiel";
    platforms = lib.platforms.unix;
  };
})
