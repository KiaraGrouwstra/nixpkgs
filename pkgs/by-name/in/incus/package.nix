import ./generic.nix {
  hash = "sha256-7s2gc+78O8jKypVe1itaUrsLPa2mLjNgUUrR/cv7ITA=";
  version = "7.0.0";
  vendorHash = "sha256-6irMB3hpWcxDuMQBxWXnhMLAOwTAl63JX6JJZMQXf5E=";
  patches = [ ];
  nixUpdateExtraArgs = [
    "--override-filename=pkgs/by-name/in/incus/package.nix"
  ];
}
