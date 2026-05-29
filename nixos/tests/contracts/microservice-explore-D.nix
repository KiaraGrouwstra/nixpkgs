# Exploration: micro-service-style eval-time contract exchange with
# the isolation boundary moved from NixOS nodes down to NixOS modular
# services co-located on one NixOS node (Variant D).
#
# Scenario: a single NixOS node (`host`) hosting three modular services
# (alice, bob, carol) declared via `system.services.<name>`. The peer
# set for contract resolution is the service set, not the host set --
# the framing where the peer is a NixOS modular service rather than a
# host. Three contracts with distinct field types (bool / int / str),
# and a per-contract routing knob that switches between centralised
# (one service answers everyone) and local (each service answers only
# itself).
#
# Like Variant A, all peers' wants and all contracts' handlers are
# composed in a SINGLE shared `lib.evalModules` call. The host then
# routes each service's slice through that service's `configData`, so
# the NixOS modular-services integration is what creates the per-service
# `/etc/system-services/<service>/contracts-explore/...` subtree on
# disk. Each service is a real systemd unit (a trivial `sleep infinity`)
# so the slot is structural, not just a path convention.
#
# A/B/C explored the eval-shape axis (one eval / per-contract /
# per-routing-scope) with peers = NixOS nodes. D keeps A's single
# shared eval but shifts the peer axis to NixOS modular services; E
# does the same and distributes the services across NixOS nodes.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types;

  slotNames = [ "alice" "bob" "carol" ];
  slotIndex = name: lib.lists.findFirstIndex (n: n == name) (throw "unknown slot ${name}") slotNames;

  # Three contracts, each at its OWN top-level option (no shared
  # `config.contracts.*` umbrella -- that is the deliberate divergence
  # from the existing contracts system for this exploration).
  contractsModule = {
    options = {
      "feature-flag" = {
        want = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.enabled = mkOption { type = types.bool; };
          });
        };
        result = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.evaluated = mkOption { type = types.bool; };
          });
        };
      };
      "port-allocation" = {
        want = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.preferred = mkOption { type = types.int; };
          });
        };
        result = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.assigned = mkOption { type = types.int; };
          });
        };
      };
      "greeting-message" = {
        want = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.name = mkOption { type = types.str; };
          });
        };
        result = mkOption {
          default = { };
          type = types.attrsOf (types.submodule {
            options.text = mkOption { type = types.str; };
          });
        };
      };
    };
  };

  # Per-contract routing decisions. `handler = null` means local
  # (each slot answers only its own want); a slot name means
  # centralised (that slot "owns" the result table, conceptually).
  # In Variant D the eval is shared anyway, so `handler` only changes
  # what each slot bakes -- not how results are computed.
  routes = {
    "feature-flag" = {
      handler = "alice";
      fulfill = { node, want }: { evaluated = want.enabled; };
    };
    "port-allocation" = {
      handler = "bob";
      fulfill = { node, want }: { assigned = want.preferred; };
    };
    "greeting-message" = {
      handler = null;
      fulfill = { node, want }: { text = "hello, ${want.name}!"; };
    };
  };

  # Module that computes `result.<slot>` from `want.<slot>` for one
  # contract using its `fulfill` function.
  routeContract = name: route: { config, ... }: {
    "${name}".result =
      lib.mapAttrs (node: want: route.fulfill { inherit node want; }) config.${name}.want;
  };

  # Each slot's wants, derived from its name/index so cross-slot
  # consistency is straightforward to assert.
  slotWantModule = name: {
    "feature-flag".want.${name}.enabled = (name == "alice");
    "port-allocation".want.${name}.preferred = 10000 + slotIndex name;
    "greeting-message".want.${name}.name = name;
  };

  sharedEval =
    (lib.evalModules {
      modules =
        [ contractsModule ]
        ++ lib.mapAttrsToList routeContract routes
        ++ map slotWantModule slotNames;
    }).config;

  # Bake selection per the routing knob: centralised contracts get
  # all peer slots' results in every slot's directory; local contracts
  # get only self.
  peersFor = slot: cName:
    if routes.${cName}.handler == null
    then [ slot ]
    else slotNames;

  # Build one `system.services.<slot>` modular service that bakes its
  # contract slice through `configData`. The NixOS systemd integration
  # writes each configData entry to
  # `/etc/system-services/${slot}/${key}`, so the slot prefix on disk
  # is provided by the service integration itself.
  mkSlotService = slot: {
    process.argv = [ "${pkgs.coreutils}/bin/sleep" "infinity" ];
    configData = lib.listToAttrs (lib.concatMap (cName:
      map (peer: lib.nameValuePair "contracts-explore/${cName}/${peer}" {
        text = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
      }) (peersFor slot cName)
    ) (lib.attrNames routes));
  };
in
{
  name = "contracts-microservice-explore-D";

  nodes.host = {
    system.services = lib.genAttrs slotNames mkSlotService;
  };

  testScript =
    let
      # Build the expected file map: for each slot, which (contract, peer)
      # files should exist and what they should contain. Paths follow
      # the modular-services integration layout: configData entries land
      # at /etc/system-services/<servicePrefix>/<key>.
      expectedFor = slot:
        lib.concatMap (cName:
          map (peer: {
            path = "/etc/system-services/${slot}/contracts-explore/${cName}/${peer}";
            content = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
          }) (peersFor slot cName)
        ) (lib.attrNames routes);

      pyDictFor = slot:
        "{" + lib.concatMapStringsSep ", " (e:
          "${builtins.toJSON e.path}: ${builtins.toJSON e.content}"
        ) (expectedFor slot) + "}";

      missingFor = slot:
        lib.concatMap (cName:
          let allOthers = lib.subtractLists (peersFor slot cName) slotNames; in
          map (peer: "/etc/system-services/${slot}/contracts-explore/${cName}/${peer}") allOthers
        ) (lib.attrNames routes);

      pyListFor = slot:
        "[" + lib.concatMapStringsSep ", " builtins.toJSON (missingFor slot) + "]";
    in
    ''
      host.wait_for_unit("multi-user.target")

      # Each slot is a real modular service; confirm the systemd units
      # the modular-services integration generates are up.
      ${lib.concatMapStringsSep "\n" (s:
        ''host.wait_for_unit("${s}.service")''
      ) slotNames}

      for slot, expected, must_be_absent in [
      ${lib.concatMapStringsSep ",\n" (s:
        "    (${builtins.toJSON s}, ${pyDictFor s}, ${pyListFor s})"
      ) slotNames}
      ]:
          for path, want in expected.items():
              got = host.succeed(f"cat {path}").rstrip("\n")
              assert got == want, f"{slot} {path}: expected {want!r}, got {got!r}"
          for path in must_be_absent:
              host.fail(f"test -e {path}")
    '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
