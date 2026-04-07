{
  lib,
  buildGoModule,
  fetchFromGitea,
}:
buildGoModule {
  pname = "systemd-openbaod";
  version = "0.0.0-unstable-2026-05-29";
  # Sourced from a fork of the-distro/systemd-openbao that gates empty-template
  # openbao agents and makes the agent package configurable, pending an upstream
  # PR back to the-distro. The NixOS modules under nix/modules/ are imported
  # from this same revision by services/security/systemd-openbaod.nix, so the
  # daemon and the modules stay in lockstep.
  src = fetchFromGitea {
    domain = "git.lix.systems";
    owner = "kiaragrouwstra";
    repo = "systemd-openbao";
    rev = "d4baef0f4904dce66a70993593c114ff7e8b13e6";
    hash = "sha256-4BK35mtXFHHkrRZ+pxdjb+pKzsuLYy/E4fURgqk6oQE=";
  };
  vendorHash = null;
  meta = {
    description = "Proxy for secrets between systemd services and openbao";
    homepage = "https://git.lix.systems/the-distro/systemd-openbao.git";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ kiara ];
    platforms = lib.platforms.unix;
    mainProgram = "systemd-openbaod";
  };
}
