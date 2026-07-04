{
  lib,
  buildGoModule,
  fetchFromGitea,
}:
buildGoModule {
  pname = "systemd-openbaod";
  version = "0.0.0-unstable-2026-05-29";
  # Sourced from a fork of the-distro/systemd-openbao that gates empty-template
  # openbao agents, makes the agent package configurable, and adds the
  # `services.openbao.agents.<name>.extraTemplates` merge point, pending an
  # upstream PR back to the-distro. The NixOS modules under nix/modules/ are
  # imported from this same revision by services/security/systemd-openbaod.nix,
  # so the daemon and the modules stay in lockstep.
  src = fetchFromGitea {
    domain = "git.lix.systems";
    owner = "kiaragrouwstra";
    repo = "systemd-openbao";
    rev = "bde10de699a3f25834134f7374e3a9f557c19fac";
    hash = "sha256-36zy/0Nqpgd7xvwrg/2N+dtQTOT8F8UZbMohueF/jD4=";
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
