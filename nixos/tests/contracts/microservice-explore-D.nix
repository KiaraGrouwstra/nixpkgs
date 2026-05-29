# Exploration: micro-service-style eval-time contract exchange with
# the isolation boundary moved from NixOS nodes down to service slots
# co-located on one NixOS node (Variant D).
#
# Scenario: a single NixOS node (`host`) hosting three modular service
# slots (alice, bob, carol). The peer set for contract resolution is
# the slot set, not the host set -- the bc3eac2b framing where the
# peer is a service slot rather than a host. Three contracts with
# distinct field types (bool / int / str), and a per-contract routing
# knob that switches between centralised (one slot answers everyone)
# and local (each slot answers only itself).
#
# Like Variant A, all slots' wants and all contracts' handlers are
# composed in a SINGLE shared `lib.evalModules` call. The host then
# bakes each slot's slice into `/etc/contracts-explore/<slot>/...` at
# config-eval time, so per-service-slot isolation is visible in the
# filesystem even though everything runs on one host.
#
# A/B/C explored the eval-shape axis (one eval / per-contract /
# per-routing-scope) with peers = NixOS nodes. D keeps A's single
# shared eval but shifts the peer axis to service slots; E does the
# same and distributes the slots across NixOS nodes.
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

  mkNode = _: {
    environment.etc = lib.listToAttrs (lib.concatMap (slot:
      lib.concatMap (cName:
        map (peer: lib.nameValuePair "contracts-explore/${slot}/${cName}/${peer}" {
          text = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
        }) (peersFor slot cName)
      ) (lib.attrNames routes)
    ) slotNames);
  };
in
{
  name = "contracts-microservice-explore-D";

  nodes.host = mkNode null;

  testScript =
    let
      # Build the expected file map: for each slot, which (contract, peer)
      # files should exist and what they should contain.
      expectedFor = slot:
        lib.concatMap (cName:
          map (peer: {
            path = "/etc/contracts-explore/${slot}/${cName}/${peer}";
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
          map (peer: "/etc/contracts-explore/${slot}/${cName}/${peer}") allOthers
        ) (lib.attrNames routes);

      pyListFor = slot:
        "[" + lib.concatMapStringsSep ", " builtins.toJSON (missingFor slot) + "]";
    in
    ''
      host.wait_for_unit("multi-user.target")

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
