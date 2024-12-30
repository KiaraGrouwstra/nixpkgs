{
  lib,
  buildGoModule,
  nym-vpn-core,
}:
buildGoModule rec {
  pname = "libwg";

  inherit (nym-vpn-core)
    version
    src
    ;

  modRoot = "${src.name}/wireguard";
  # proxyVendor = true;
  # vendorHash = "";

  # XXX: hack to make the ar archive go to the correct place
  # This is necessary because passing `-o ...` to `ldflags` does not work
  # (this doesn't get communicated everywhere in the chain, apparently, so
  # `go` complains that it can't find an `a.out` file).
  # GOBIN = "${placeholder "out"}/lib";

  # subPackages = [ "." ];
  # ldflags = [
  #   "-s"
  #   "-w"
  #   "-buildmode=c-archive"
  # ];
  # tags = [ "daita" ];

  # postInstall = ''
  #   mv $out/lib/libwg{,.a}
  # '';

  meta = with lib; {
    description = "Tiny wrapper around wireguard-go";
    homepage = "https://github.com/nymtech/nym-vpn-client/tree/develop/wireguard/libwg";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ KiaraGrouwstra ];
  };
}
