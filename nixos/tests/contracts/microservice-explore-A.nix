# Exploration: micro-service-style eval-time contract exchange across
# N nodes and M heterogeneous contract shapes, using a SINGLE shared
# `lib.evalModules` call (Variant A).
#
# Scenario: three nodes (alice, bob, carol), three contracts with
# distinct field types (bool / int / str), and a per-contract routing
# knob that switches between centralised (one handler answers everyone)
# and local (each node answers only itself).
#
# Variant A composes every node's `want` and every contract's handler
# in one module-system evaluation. Each NixOS node then bakes the
# resulting slice it cares about into `/etc/contracts-explore/...` at
# config-eval time. The VM exists only so we can observe that two
# separately-evaluated NixOS configurations end up agreeing on the
# values produced by the shared eval -- no real inter-node services.
#
# Note: cross-contract chaining (a contract whose `fulfill` reads
# another contract's `result`) is naturally supported by Variant A
# because every contract lives in the same eval; not exercised here.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types;

  nodeNames = [ "alice" "bob" "carol" ];
  nodeIndex = name: lib.lists.findFirstIndex (n: n == name) (throw "unknown node ${name}") nodeNames;

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
  # (each node answers only its own want); a node name means
  # centralised (that node "owns" the result table, conceptually).
  # In Variant A the eval is shared anyway, so `handler` only changes
  # what each node bakes -- not how results are computed.
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

  # Module that computes `result.<node>` from `want.<node>` for one
  # contract using its `fulfill` function.
  routeContract = name: route: { config, ... }: {
    "${name}".result =
      lib.mapAttrs (node: want: route.fulfill { inherit node want; }) config.${name}.want;
  };

  # Each node's wants, derived from its name/index so cross-node
  # consistency is straightforward to assert.
  nodeWantModule = name: {
    "feature-flag".want.${name}.enabled = (name == "alice");
    "port-allocation".want.${name}.preferred = 10000 + nodeIndex name;
    "greeting-message".want.${name}.name = name;
  };

  sharedEval =
    (lib.evalModules {
      modules =
        [ contractsModule ]
        ++ lib.mapAttrsToList routeContract routes
        ++ map nodeWantModule nodeNames;
    }).config;

  # Bake selection per the routing knob: centralised contracts get
  # all peers' results on every node; local contracts get only self.
  peersFor = node: cName:
    if routes.${cName}.handler == null
    then [ node ]
    else nodeNames;

  mkNode = node: {
    environment.etc = lib.listToAttrs (lib.concatMap (cName:
      map (peer: lib.nameValuePair "contracts-explore/${cName}/${peer}" {
        text = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
      }) (peersFor node cName)
    ) (lib.attrNames routes));
  };
in
{
  name = "contracts-microservice-explore-A";

  nodes = lib.genAttrs nodeNames mkNode;

  testScript =
    let
      # Build the expected file map: for each node, which (contract, peer)
      # files should exist and what they should contain.
      expectedFor = node:
        lib.concatMap (cName:
          map (peer: {
            path = "/etc/contracts-explore/${cName}/${peer}";
            content = lib.generators.toPretty { multiline = false; } sharedEval.${cName}.result.${peer};
          }) (peersFor node cName)
        ) (lib.attrNames routes);

      pyDictFor = node:
        "{" + lib.concatMapStringsSep ", " (e:
          "${builtins.toJSON e.path}: ${builtins.toJSON e.content}"
        ) (expectedFor node) + "}";

      missingFor = node:
        lib.concatMap (cName:
          let allOthers = lib.subtractLists (peersFor node cName) nodeNames; in
          map (peer: "/etc/contracts-explore/${cName}/${peer}") allOthers
        ) (lib.attrNames routes);

      pyListFor = node:
        "[" + lib.concatMapStringsSep ", " builtins.toJSON (missingFor node) + "]";
    in
    ''
      ${lib.concatMapStringsSep "\n" (n: "${n}.wait_for_unit(\"multi-user.target\")") nodeNames}

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
