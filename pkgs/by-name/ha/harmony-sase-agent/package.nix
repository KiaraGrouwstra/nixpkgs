{
  lib,
  autoPatchelfHook,
  stdenv,
  fetchurl,
  atk,
  dbus,
  gdk-pixbuf,
  gtk3,
  pango,
  cairo,
  expat,
  libxkbcommon,
  mesa,
  alsa-lib,
  cups,
  libgcc,
  nspr,
  nss,
  xorg,
  ...
}:
stdenv.mkDerivation rec {
  pname = "harmony-sase-agent";
  version = "9.0.1.843";

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/lib
    cp perimeter81 $out/bin
    cp libffmpeg.so $out/lib

  '';

  buildInputs = [
    atk
    dbus
    gdk-pixbuf
    gtk3
    pango
    cairo
    expat
    libxkbcommon
    mesa
    alsa-lib
    cups
    libgcc
    nspr
    nss
    xorg.libX11
    xorg.libxcb
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxshmfence
  ];

  nativeBuildInputs = [ autoPatchelfHook ];

  src = fetchurl {
    url = "https://static.perimeter81.com/agents/linux/Perimeter81_${version}.tar.xz";
    sha256 = "sha256-4ofZ/x5xZpjVqKJrvFLpTbxe8gty7nLmwB0jzVMHDqE=";
  };

  meta = with lib; {
    homepage = "https://www.perimeter81.com/";
    description = "Agent for Perimeter 81's service Secure Access Service Edge.";
    mainProgram = "perimeter81";
    maintainers = teams.gnome.members;
    license = licenses.gpl2;
    platforms = platforms.unix;
  };
}
