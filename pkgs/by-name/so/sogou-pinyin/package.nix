{
  alsa-lib,
  autoPatchelfHook,
  cairo,
  dbus,
  fcitx,
  fcitx-configtool,
  lib,
  libgcc,
  libGL,
  librsvg,
  libsForQt5,
  pulseaudio,
  stdenv,
  fetchurl,
  dpkg,
  waylandpp,
  xorg,
}:

stdenv.mkDerivation rec {
  pname = "sogou-pinyin";
  version = "4.2.1.145";

  src = fetchurl {
    # updating: https://shurufa.sogou.com/linux -> download -> select architecture -> archive link
    url = "https://web.archive.org/web/20250215074054/https://ime-sec.gtimg.com/202502151538/ee820f734cadd373a22be53b0d194b61/pc/dl/gzindex/1680521603/sogoupinyin_4.2.1.145_amd64.deb";
    sha256 = "sha256-MRGvF6ar3dgLhWqpwfV5oTfWnz1zXq2TbdtuXwi1nzs=";
  };

  buildInputs = [
    alsa-lib
    cairo
    dbus
    fcitx
    fcitx-configtool
    libgcc
    libGL
    librsvg
    libsForQt5.libdbusmenu
    pulseaudio
    waylandpp
    xorg.libICE
    xorg.libXcursor
    xorg.libXext
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXtst
    xorg.libXxf86vm
  ];

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  # dontBuild = true;
  # dontUnpack = true;
  # dontInstall = true;
  # dontFixup = true;

  installPhase = ''
    runHook preInstall
    pwd
    ls
    mkdir -p $out
    # mv ./ $out/
    cp -r ./ $out/
    # install -m755 -D studio-link-standalone-v${version} $out/bin/studio-link
    runHook postInstall
  '';

  meta = with lib; {
    description = "Chinese IME Sogou Pinyin";
    # longDescription = ''
    # '';
    homepage = "https://shurufa.sogou.com/";
    license = licenses.unfree;
    # maintainers = teams.jitsi.members;
    platforms = platforms.linux;
  };
}
