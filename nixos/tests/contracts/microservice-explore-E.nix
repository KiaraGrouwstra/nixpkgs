# Exploration: micro-service-style eval-time contract exchange where
# the peer is a NixOS modular service but services are distributed one
# per NixOS node (Variant E).
#
# Scenario: three NixOS nodes (n1, n2, n3), three modular services
# (alice, bob, carol) declared via `system.services.<name>`, a
# `slotHost` table that pins each service to one node, and three
# contracts with distinct field types (bool / int / str). Same
# per-contract routing knob as A/D between centralised and local; here
# a "local" contract isolates inside a single modular service, which
# also means inside a single host -- so the cross-node-cross-service
# boundary is what gets tested.
#
# Like Variant A, all services' wants and all contracts' handlers are
# composed in a SINGLE shared `lib.evalModules` call. Each NixOS node
# declares only the modular service(s) it hosts; the NixOS systemd
# integration writes each service's `configData` to
# `/etc/system-services/<service>/contracts-explore/...`, so the file
# layout per host reflects the slot-to-host mapping.
#
# E shares D's eval strategy; the only difference is that the peer
# services are spread across distinct NixOS hosts instead of co-located.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types;

  slotNames = [ "alice" "bob" "carol" ];
  slotIndex = name: lib.lists.findFirstIndex (n: n == name) (throw "unknown slot ${name}") slotNames;

  # Which NixOS node hosts each modular service. This is the only place
  # the NixOS topology and the contract peer set meet -- the shared eval
  # itself only sees service names.
  slotHost = {
    alice = "n1";
    bob = "n2";
    carol = "n3";
  };
  nodeNames = lib.unique (lib.attrValues slotHost);
  slotsOn = node: lib.filter (s: slotHost.${s} == node) slotNames;

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
  # In Variant E the eval is shared anyway, so `handler` only changes
  # what each host bakes -- not how results are computed.
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
  # all peer slots' results in every hosted slot's directory; local
  # contracts get only self.
  peersFor = slot: cName:
    if routes.${cName}.handler == null
    then [ slot ]
    else slotNames;

  # Build one `system.services.<slot>` modular service that bakes its
  # contract slice through `configData`. Files land at
  # `/etc/system-services/${slot}/...` via the modular-services
  # integration.
  mkSlotService = slot: {
    process.argv = [ "${pkgs.coreutils}/bin/sleep" "infinity" ];
    configData = lib.listToAttrs (lib.concatMap (cName:
      map (peer: lib.nameValuePair "contracts-explore/${cName}/${peer}" {
        text = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
      }) (peersFor slot cName)
    ) (lib.attrNames routes));
  };

  mkNode = node: {
    system.services = lib.genAttrs (slotsOn node) mkSlotService;
  };
in
{
  name = "contracts-microservice-explore-E";

  nodes = lib.genAttrs nodeNames mkNode;

  testScript =
    let
      # Build the expected file map: for each (node, hosted-slot) pair,
      # which (contract, peer) files should exist and what they should
      # contain. Slots not hosted on a node contribute to its absent set.
      expectedFor = node:
        lib.concatMap (slot:
          lib.concatMap (cName:
            map (peer: {
              path = "/etc/system-services/${slot}/contracts-explore/${cName}/${peer}";
              content = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
            }) (peersFor slot cName)
          ) (lib.attrNames routes)
        ) (slotsOn node);

      pyDictFor = node:
        "{" + lib.concatMapStringsSep ", " (e:
          "${builtins.toJSON e.path}: ${builtins.toJSON e.content}"
        ) (expectedFor node) + "}";

      # Files belonging to slots hosted elsewhere must not appear here.
      # Within a hosted slot, the local contract's other-peer files
      # must also not appear (matches A/D semantics).
      missingFor = node:
        let
          foreignSlots = lib.subtractLists (slotsOn node) slotNames;
          foreignPaths = lib.concatMap (slot:
            lib.concatMap (cName:
              map (peer: "/etc/system-services/${slot}/contracts-explore/${cName}/${peer}")
                (peersFor slot cName)
            ) (lib.attrNames routes)
          ) foreignSlots;
          localMissing = lib.concatMap (slot:
            lib.concatMap (cName:
              let allOthers = lib.subtractLists (peersFor slot cName) slotNames; in
              map (peer: "/etc/system-services/${slot}/contracts-explore/${cName}/${peer}") allOthers
            ) (lib.attrNames routes)
          ) (slotsOn node);
        in foreignPaths ++ localMissing;

      pyListFor = node:
        "[" + lib.concatMapStringsSep ", " builtins.toJSON (missingFor node) + "]";

      # Each hosted slot should have its modular service unit running.
      waitUnits = lib.concatMap (n:
        map (s: "${n}.wait_for_unit(\"${s}.service\")") (slotsOn n)
      ) nodeNames;
    in
    ''
      ${lib.concatMapStringsSep "\n" (n: "${n}.wait_for_unit(\"multi-user.target\")") nodeNames}

      ${lib.concatStringsSep "\n" waitUnits}

      for node, expected, must_be_absent in [
      ${lib.concatMapStringsSep ",\n" (n:
        "    (${n}, ${pyDictFor n}, ${pyListFor n})"
      ) nodeNames}
      ]:
          for path, want in expected.items():
              got = node.succeed(f"cat {path}").rstrip("\n")
              assert got == want, f"{node.name} {path}: expected {want!r}, got {got!r}"
          for path in must_be_absent:
              node.fail(f"test -e {path}")
    '';

  meta.maintainers = with lib.maintainers; [ kiara ];
}
