{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "nym-vpn-core";
  version = "1.1.1";
  sourceRoot = "${src.name}/nym-vpn-core";


  src = fetchFromGitHub {
    owner = "nymtech";
    repo = "nym-vpn-client";
    tag = "nym-vpn-core-v${version}";
    hash = "sha256-KEy+2zCsYjGn824mzAZ7k4vTG6eIs/b7s8sVTyKLMfs=";
  };

  cargoHash = "sha256-svZtxAy1Nca3hz04jE7g8JvXDg159jfp0Dxifkq4X6o=";
  useFetchCargoVendor = true;

  meta = {
    description = "Nym VPN CLI client";
    changelog = "https://github.com/nymtech/nym-vpn-client/blob/develop/CHANGELOG.md";
    homepage = "https://nymtech.net";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ KiaraGrouwstra ];
  };
}
