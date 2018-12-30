{ pkgs, fetchurl, dpkg, patchelf, fcitx, opencc, lsb-release, xprop, ... }:
# other packages references on AUR that Nix didn't see for me: qtwebkit, libidn11

let

  version = "2.2.0.0108";
  _i686_time="1524572032";
  _x86_64_time="1524572264";

  src =
    # v stdenv should work without pkgs but I didn't get that to work
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then fetchurl {
      name = "sogou-pinyin.deb";
      url = "http://cdn2.ime.sogou.com/dl/index/${_x86_64_time}/sogoupinyin_${version}_amd64.deb";
      sha256 = "0phs8gk4qz1kl64bbj15mv0r0p2frkmakhljpqgb10d12vy1yrav";
    } else if pkgs.stdenv.hostPlatform.system == "i686-linux" then fetchurl {
      name = "sogou-pinyin.deb";
      url = "http://cdn2.ime.sogou.com/dl/index/${_i686_time}/sogoupinyin_${version}_i386.deb";
      sha256 = "1qqqq9dfala476fds2nfhmb0q8kg2rskniz116z1x8ayck7xv7ic";
    } else
      throw "Sogou Pinyin is not supported on ${pkgs.stdenv.hostPlatform.system}";

in 
pkgs.stdenv.mkDerivation {
  name = "fcitx-sogoupinyin-${version}";
  # system = "x86_64-linux";  # probably don't need to specify if equal to hostPlatform.system
  inherit src;
  # nativeBuildInputs = [];
  buildInputs = [ dpkg fcitx opencc lsb-release xprop ]; # not succesfully imported: qtwebkit libidn11

  unpackPhase = "true";
  installPhase = ''
    # install logic based on AUR package:

    mkdir -p $out
    dpkg -x $src $out

    mv $out/usr/lib/*-linux-gnu/fcitx $out/usr/lib/
    rmdir $out/usr/lib/*-linux-gnu

    # Avoid warning "No such key 'Gtk/IMModule' in schema 'org.gnome.settings-daemon.plugins.xsettings'"
    sed -i "s#Gtk/IMModule=fcitx#overrides={'Gtk/IMModule':<'fcitx'>}#" $out/usr/share/glib-2.0/schemas/50_sogoupinyin.gschema.override

    rm -r $out/usr/share/keyrings
    rm -r $out/etc/X11
  '';

  postFixup = ''
    # ELF patching, which I found in many other Nix derivations of proprietary deb packages:

    for file in $(find $out -type f \( -perm /0111 -o -name \*.so\* \) ); do
      ${patchelf}/bin/patchelf \
        --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        --set-rpath "${pkgs.stdenv.lib.makeLibraryPath [ fcitx opencc lsb-release xprop ]}" \
        "$file" || true
        # ^ not listed in rpath: qtwebkit libidn11
    done

    # install -m755 sogou-autostart $out/usr/bin
    # ^ I'm not sure what this sogou-autostart is

    # Do not modify $out/etc/xdg/autostart/fcitx-ui-sogou-qimpanel.desktop, as it is
    # a symlink to absolute path "/usr/share/applications/fcitx-ui-sogou-qimpanel.desktop"
    # sed -i 's/sogou-qimpanel\ %U/sogou-autostart/g' $out/usr/share/applications/fcitx-ui-sogou-qimpanel.desktop
    # ^ commented bit from the AUR package

    # # Fix the desktop link
    # substituteInPlace $out/usr/share/applications/fcitx-ui-sogou-qimpanel.desktop \
    #   --replace sogou-qimpanel $out/usr/bin/sogou-qimpanel
    # ^ alternative, didn't get either to work

  '';

  meta = with pkgs.stdenv.lib; {
    description = "Sogou Pinyin for Linux";
    homepage = https://pinyin.sogou.com/linux/;
    license = licenses.unfree;
    # maintainers = with maintainers; [];
    platforms = [ "x86_64-linux" "i686-linux" ];
  };

}
