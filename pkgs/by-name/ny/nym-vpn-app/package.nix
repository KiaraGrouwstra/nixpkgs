{
  lib,
  fetchFromGitHub,
  buildNpmPackage,
  importNpmLock,
}:

buildNpmPackage rec {
  pname = "nym-vpn-app";
  version = "1.1.0";
  sourceRoot = "${src.name}/nym-vpn-app";

  src = fetchFromGitHub {
    owner = "nymtech";
    repo = "nym-vpn-client";
    tag = "nym-vpn-app-v${version}";
    hash = "sha256-jrY+IyeoaQ3ia1LNGt4bjTJXMA7AeS0stNXUTL6fsXI=";
  };

  npmDeps = importNpmLock {
    # npmRoot = ./.;
    npmRoot = "${src.name}/nym-vpn-app";
    # fetcherOpts = {
    #   # Pass 'curlOptsList' to 'pkgs.fetchurl' while fetching 'axios'
    #   { "node_modules/axios" = { curlOptsList = [ "--verbose" ]; }; }
    # };
  };

  # cargoHash = "";
  # useFetchCargoVendor = true;

  frontend = buildNpmPackage {
    inherit version src;
    pname = "nym-vpn-app-ui";
    # # FIXME: This is a workaround, because we have a git dependency node_modules/lrc-kit contains install scripts
    # # but has no lockfile, which is something that will probably break.
    # forceGitDeps = true;
    # distPhase = "true";
    # dontInstall = true;
    # # To fix `npm ERR! Your cache folder contains root-owned files`
    # makeCacheWritable = true;

    # npmDepsHash = "sha256-N48+C3NNPYg/rOpnRNmkZfZU/ZHp8imrG/tiDaMGsCE=";

    postBuild = ''
      cp -r dist/ $out
    '';
  };

  # # copy the frontend static resources to final build directory
  # # Also modify tauri.conf.json so that it expects the resources at the new location
  # postPatch = ''
  #   cp -r $frontend ./frontend

  #   substituteInPlace tauri.conf.json \
  #     --replace-fail '"frontendDist": "../dist"' '"frontendDist": "./frontend"'
  # '';

  meta = {
    description = "Nym VPN web client";
    changelog = "https://github.com/nymtech/nym-vpn-client/blob/develop/CHANGELOG.md";
    homepage = "https://nymtech.net";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ KiaraGrouwstra ];
  };
}
