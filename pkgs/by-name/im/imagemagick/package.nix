{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  libtool,
  bzip2Support ? !stdenv.hostPlatform.isWasi,
  bzip2,
  zlibSupport ? true,
  zlib,
  libX11Support ? !(stdenv.hostPlatform.isMinGW || stdenv.hostPlatform.isWasi),
  libx11,
  libXtSupport ? !(stdenv.hostPlatform.isMinGW || stdenv.hostPlatform.isWasi),
  libxt,
  fontconfigSupport ? !stdenv.hostPlatform.isWasi,
  fontconfig,
  freetypeSupport ? !stdenv.hostPlatform.isWasi,
  freetype,
  ghostscriptSupport ? false,
  ghostscript,
  libjpegSupport ? true,
  libjpeg,
  djvulibreSupport ? !stdenv.hostPlatform.isWasi,
  djvulibre,
  lcms2Support ? !stdenv.hostPlatform.isWasi,
  lcms2,
  openexrSupport ? !(stdenv.hostPlatform.isMinGW || stdenv.hostPlatform.isWasi),
  openexr,
  libjxlSupport ? !stdenv.hostPlatform.isWasi,
  libjxl,
  libpngSupport ? true,
  libpng,
  liblqr1Support ? !stdenv.hostPlatform.isWasi,
  liblqr1,
  libraqmSupport ? !stdenv.hostPlatform.isWasi,
  libraqm,
  librawSupport ? !stdenv.hostPlatform.isWasi,
  libraw,
  librsvgSupport ? !(stdenv.hostPlatform.isMinGW || stdenv.hostPlatform.isWasi),
  librsvg,
  pango,
  libtiffSupport ? true,
  libtiff,
  libultrahdrSupport ?
    lib.meta.availableOn stdenv.hostPlatform libultrahdr && !stdenv.hostPlatform.isWasi,
  libultrahdr,
  libxml2Support ? !stdenv.hostPlatform.isWasi,
  libxml2,
  openjpegSupport ? !(stdenv.hostPlatform.isMinGW || stdenv.hostPlatform.isWasi),
  openjpeg,
  libwebpSupport ? !stdenv.hostPlatform.isMinGW,
  libwebp,
  libheifSupport ? !stdenv.hostPlatform.isWasi,
  libheif,
  fftwSupport ? !stdenv.hostPlatform.isWasi,
  fftw,
  potrace,
  coreutils,
  curl,
  versionCheckHook,
  testers,
  nixos-icons,
  perlPackages,
  python3,
  nix-update-script,
}:

assert libXtSupport -> libX11Support;
assert libraqmSupport -> freetypeSupport;

stdenv.mkDerivation (finalAttrs: {
  pname = "imagemagick";
  version = "7.1.2-34";

  src = fetchFromGitHub {
    owner = "ImageMagick";
    repo = "ImageMagick";
    tag = finalAttrs.version;
    hash = "sha256-H2tXlEsW2JbvJJpUxEkwbV3zRXjwtPBxpbvs2xdKNZY=";
  };

  outputs = [
    "out"
    "dev"
    "doc"
  ]; # bin/ isn't really big
  outputMan = "out"; # it's tiny

  enableParallelBuilding = true;

  configureFlags =
    # specify delegates explicitly otherwise `convert` will invoke the build
    # coreutils for filetypes it doesn't natively support.
    # WASI cannot start processes, thus it cannot use delegates.
    lib.optionals (!stdenv.hostPlatform.isWasi) [
      "MVDelegate=${lib.getExe' coreutils "mv"}"
      "RMDelegate=${lib.getExe' coreutils "rm"}"
    ]
    ++ [
      "--with-frozenpaths"
      "--with-gcc-arch=generic"
      (lib.withFeature librsvgSupport "rsvg")
      (lib.withFeature librsvgSupport "pango")
      (lib.withFeature liblqr1Support "lqr")
      (lib.withFeature libjxlSupport "jxl")
      (lib.withFeature libultrahdrSupport "uhdr")
      (lib.withFeatureAs ghostscriptSupport "gs-font-dir" "${ghostscript.fonts}/share/fonts")
      (lib.withFeature ghostscriptSupport "gslib")
      (lib.withFeature fftwSupport "fftw")
    ]
    ++ lib.optionals stdenv.hostPlatform.isMinGW [
      # due to libxml2 being without DLLs ATM
      "--enable-static"
      "--disable-shared"
    ]
    # The WASI C++ toolchain has no exceptions, which Magick++ needs.
    ++ lib.optional stdenv.hostPlatform.isWasi "--without-magick-plus-plus";

  # WASI has no processes, `pwd.h` or `sys/wait.h`.
  patches = lib.optional stdenv.hostPlatform.isWasi ./wasi.patch;

  env = lib.optionalAttrs stdenv.hostPlatform.isWasi {
    # WASI has `setjmp` only through the exception handling proposal.
    # The JPEG and PNG coders use it.
    # wasi-libc supplies signals, `clock` and `getpid` only as emulations.
    NIX_CFLAGS_COMPILE = toString [
      "-mexception-handling"
      "-mllvm -wasm-enable-sjlj"
      "-mllvm -wasm-use-legacy-eh=false"
      "-D_WASI_EMULATED_SIGNAL"
      "-D_WASI_EMULATED_PROCESS_CLOCKS"
      "-D_WASI_EMULATED_GETPID"
    ];
    # The default stack of 64 KiB is too small, and an overflow writes over the static data.
    # Thus use a larger stack, and put it first, so that an overflow traps.
    NIX_LDFLAGS = toString [
      "-lsetjmp"
      "-lwasi-emulated-signal"
      "-lwasi-emulated-process-clocks"
      "-lwasi-emulated-getpid"
      "-z stack-size=8388608"
      "--stack-first"
    ];
  };

  nativeBuildInputs = [
    pkg-config
    libtool
  ];

  buildInputs = [
    potrace
  ]
  ++ lib.optional zlibSupport zlib
  ++ lib.optional fontconfigSupport fontconfig
  ++ lib.optional ghostscriptSupport ghostscript
  ++ lib.optional liblqr1Support liblqr1
  ++ lib.optional libpngSupport libpng
  ++ lib.optional libraqmSupport libraqm
  ++ lib.optional librawSupport libraw
  ++ lib.optional libtiffSupport libtiff
  ++ lib.optional libultrahdrSupport libultrahdr
  ++ lib.optional libxml2Support libxml2
  ++ lib.optional libheifSupport libheif
  ++ lib.optional djvulibreSupport djvulibre
  ++ lib.optional libjxlSupport libjxl
  ++ lib.optional openexrSupport openexr
  ++ lib.optionals librsvgSupport [
    librsvg
    pango
  ]
  ++ lib.optional openjpegSupport openjpeg;

  propagatedBuildInputs =
    # WASI has no sockets, thus curl cannot build.
    lib.optional (!stdenv.hostPlatform.isWasi) curl
    ++ lib.optional bzip2Support bzip2
    ++ lib.optional freetypeSupport freetype
    ++ lib.optional libjpegSupport libjpeg
    ++ lib.optional lcms2Support lcms2
    ++ lib.optional libX11Support libx11
    ++ lib.optional libXtSupport libxt
    ++ lib.optional libwebpSupport libwebp
    ++ lib.optional fftwSupport fftw;

  postInstall = ''
    (cd "$dev/include" && ln -s ImageMagick* ImageMagick)
    # Q16HDRI = 16 bit quantum depth with HDRI support, and is the default ImageMagick configuration
    # If the default is changed, or the derivation is modified to use a different configuration
    # this will need to be changed below.
    moveToOutput "bin/*-config" "$dev"
    moveToOutput "lib/ImageMagick-*/config-Q16HDRI" "$dev" # includes configure params
    configDestination=($out/share/ImageMagick-*)
    grep -v "$NIX_STORE" $dev/lib/ImageMagick-*/config-Q16HDRI/configure.xml > $configDestination/configure.xml
    for file in "$dev"/bin/*-config; do
      substituteInPlace "$file" --replace-fail "$PKG_CONFIG" \
        "PKG_CONFIG_PATH='$dev/lib/pkgconfig' '$(command -v $PKG_CONFIG)'"
    done
  ''
  + lib.optionalString ghostscriptSupport ''
    for la in $out/lib/*.la; do
      sed 's|-lgs|-L${lib.getLib ghostscript}/lib -lgs|' -i $la
    done
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [
    versionCheckHook
  ];

  passthru.tests = {
    inherit nixos-icons;
    inherit (perlPackages) ImageMagick;
    inherit (python3.pkgs) img2pdf willow;
    pkg-config = testers.hasPkgConfigModules {
      package = finalAttrs.finalPackage;
      version = lib.head (lib.splitString "-" finalAttrs.version);
    };
  };

  passthru.updateScript = nix-update-script { };

  meta = {
    homepage = "http://www.imagemagick.org/";
    changelog = "https://github.com/ImageMagick/Website/blob/main/docs/changelog/index.md";
    description = "Software suite to create, edit, compose, or convert bitmap images";
    pkgConfigModules = [
      "ImageMagick"
      "MagickWand"
    ];
    platforms = lib.platforms.unix ++ lib.platforms.wasi;
    maintainers = with lib.maintainers; [
      dotlambda
      rhendric
      faukah
    ];
    license = lib.licenses.asl20;
    mainProgram = "magick";
  };
})
