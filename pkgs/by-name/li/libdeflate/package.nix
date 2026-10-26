{
  lib,
  stdenv,
  fetchFromGitHub,
  fixDarwinDylibNames,
  pkgsStatic,
  cmake,
  zlib,
  testers,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libdeflate";
  version = "1.26";

  src = fetchFromGitHub {
    owner = "ebiggers";
    repo = "libdeflate";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QVF2XL8Qu3mTszKKtx+8BExkTGkpMANXjkAe3XXPUJQ=";
  };

  cmakeFlags = [
    "-DLIBDEFLATE_BUILD_TESTS=ON"
  ]
  ++ lib.optionals stdenv.hostPlatform.isStatic [ "-DLIBDEFLATE_BUILD_SHARED_LIB=OFF" ]
  ++ lib.optionals stdenv.hostPlatform.isWasi [
    # The programs and the tests use `mmap`, which WASI does not have.
    "-DLIBDEFLATE_BUILD_GZIP=OFF"
    "-DLIBDEFLATE_BUILD_TESTS=OFF"
  ];

  nativeBuildInputs = [ cmake ] ++ lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;
  buildInputs = [ zlib ];

  strictDeps = true;

  passthru.tests = {
    static = pkgsStatic.libdeflate;
    pkg-config = testers.hasPkgConfigModules {
      package = finalAttrs.finalPackage;
    };
  };

  doCheck = true;

  __structuredAttrs = true;

  meta = {
    description = "Fast DEFLATE/zlib/gzip compressor and decompressor";
    license = lib.licenses.mit;
    homepage = "https://github.com/ebiggers/libdeflate";
    changelog = "https://github.com/ebiggers/libdeflate/blob/v${finalAttrs.version}/NEWS.md";
    platforms = lib.platforms.unix ++ lib.platforms.windows ++ lib.platforms.wasi;
    maintainers = with lib.maintainers; [
      kaction
    ];
    pkgConfigModules = [ "libdeflate" ];
  };
})
