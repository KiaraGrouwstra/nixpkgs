{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
, fcitx5
, opencc
, lsb-release
, xprop
}:

let
  version = "4.2.1.145";
in
stdenv.mkDerivation {
  name = "fcitx5-sogou-pinyin-${version}";
  src = fetchurl {
    name = "sogou-pinyin.deb";
    url = "https://ime-sec.gtimg.com/202402142154/3e8acc7b8894e2632d9081fb19185e7b/pc/dl/gzindex/1680521603/sogoupinyin_${version}_amd64.deb";
    sha256 = "3111af17a6abddd80b856aa9c1f579a137d69f3d735ead936ddb6e5f08b59f3b";
  };
  buildInputs = [ dpkg fcitx5 opencc lsb-release xprop ];

  meta = with lib; {
    description = "Sogou Pinyin for Linux";
    homepage = https://shurufa.sogou.com/linux;
    license = licenses.unfree;
    maintainers = with maintainers; [ KiaraGrouwstra ];
    platforms = [ "x86_64-linux" ];
  };

}
