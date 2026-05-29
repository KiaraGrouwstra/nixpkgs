# systemd-openbaod: broker secrets from OpenBao to systemd services.
#
# This module is a thin bridge to the NixOS modules shipped with the-distro's
# systemd-openbao, fetched at the same revision that `pkgs.systemd-openbaod` is
# built from so the daemon and its modules stay in lockstep. Rather than
# re-implementing the broker here, it imports:
#
#   - systemd-openbaod.nix: the `/run/systemd-openbaod/sock` socket + daemon,
#     plus (via openbao-secrets.nix) per-service `vault.*` options that deliver
#     secrets through `LoadCredential` / `EnvironmentFile` and run
#     `try-reload-or-restart` on rotation.
#   - openbao-agent.nix: `services.openbao.agents.<name>`, each running
#     `bao agent` to render the templates the services above declare. An agent
#     with no templates is disabled, so the unit stays absent until a service
#     actually targets it.
#
# The source is fetched with `builtins.fetchTarball` (a fixed-output fetch, not
# IFD) mirroring the npins pattern, so eval stays pure. The revision and hash
# track `pkgs/by-name/sy/systemd-openbaod/package.nix`; bump both together.
#
# The daemon's systemd service is socket-activated (it is not wanted by any
# target), so on a host that declares no agents and no `vault.*` secrets only
# the unix socket is created and the daemon never starts. Opt-in gating of the
# socket itself is left to a follow-up PR against the-distro.
{ pkgs, ... }:
let
  src = builtins.fetchTarball {
    url = "https://git.lix.systems/kiaragrouwstra/systemd-openbao/archive/d4baef0f4904dce66a70993593c114ff7e8b13e6.tar.gz";
    sha256 = "00d17alq44gmw722yqwbrg74mskgccbsfzhnmpj7252pdgkbf4p0";
  };
in
{
  imports = [
    "${src}/nix/modules/systemd-openbaod.nix" # also pulls in openbao-secrets.nix
    "${src}/nix/modules/openbao-agent.nix"
  ];

  # One source of truth for the daemon binary: the nixpkgs package built from
  # the same revision the imported modules come from.
  services.systemd-openbaod.package = pkgs.systemd-openbaod;
}
