{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    cargo
    rustc
    clippy
    rustfmt
    pkg-config
  ];
  buildInputs = with pkgs; [ openssl ];
}
