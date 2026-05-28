# Exploration: same scenario as variants A and B, but split by ROUTING
# SCOPE (Variant C). Each centralised contract gets one shared
# `lib.evalModules` call aggregating wants from all nodes for that
# contract's handler; each local contract gets per-node evals (each
# tiny, no cross-node visibility).
#
# Conceptually closest to a real micro-service deployment:
#   - a "centralised service" has one deployment that sees all clients;
#   - a "local service" runs independently on every host.
#
# Compared to Variant A (one big eval) this trades implicit chaining
# for stronger boundary clarity per routing scope; compared to Variant B
# (per-contract eval, but each still global across nodes) it actually
# *shrinks* the eval graph for local contracts.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types;

  nodeNames = [ "alice" "bob" "carol" ];
  nodeIndex = name: lib.lists.findFirstIndex (n: n == name) (throw "unknown node ${name}") nodeNames;

  contracts = {
    "feature-flag" = {
      wantOptions.enabled = mkOption { type = types.bool; };
      resultOptions.evaluated = mkOption { type = types.bool; };
      wantFor = name: { enabled = (name == "alice"); };
      handler = "alice";
      fulfill = { node, want }: { evaluated = want.enabled; };
    };
    "port-allocation" = {
      wantOptions.preferred = mkOption { type = types.int; };
      resultOptions.assigned = mkOption { type = types.int; };
      wantFor = name: { preferred = 10000 + nodeIndex name; };
      handler = "bob";
      fulfill = { node, want }: { assigned = want.preferred; };
    };
    "greeting-message" = {
      wantOptions.name = mkOption { type = types.str; };
      resultOptions.text = mkOption { type = types.str; };
      wantFor = name: { name = name; };
      handler = null;
      fulfill = { node, want }: { text = "hello, ${want.name}!"; };
    };
  };

  # Schema module for one contract, used by both routing scopes.
  contractSchema = cName: c: {
    options.${cName} = {
      want = mkOption {
        default = { };
        type = types.attrsOf (types.submodule { options = c.wantOptions; });
      };
      result = mkOption {
        default = { };
        type = types.attrsOf (types.submodule { options = c.resultOptions; });
      };
    };
  };

  # Centralised scope: one eval aggregating every node's want for this
  # contract; the handler computes the full result table.
  evalCentralised = cName: c:
    (lib.evalModules {
      modules = [
        (contractSchema cName c)
        ({ config, ... }: {
          ${cName} = {
            want = lib.genAttrs nodeNames c.wantFor;
            result =
              lib.mapAttrs (node: want: c.fulfill { inherit node want; }) config.${cName}.want;
          };
        })
      ];
    }).config.${cName};

  # Local scope: one tiny eval per node, seeing only that node's want.
  evalLocalOnNode = cName: c: node:
    (lib.evalModules {
      modules = [
        (contractSchema cName c)
        ({ config, ... }: {
          ${cName} = {
            want.${node} = c.wantFor node;
            result =
              lib.mapAttrs (n: want: c.fulfill { node = n; inherit want; }) config.${cName}.want;
          };
        })
      ];
    }).config.${cName};

  # For each contract, build a lookup `cName -> node -> resultForThatNode`
  # so the bake site below doesn't care which scope produced it.
  resultsByContractByNode = lib.mapAttrs (cName: c:
    if c.handler == null
    then lib.genAttrs nodeNames (n: (evalLocalOnNode cName c n).result.${n})
    else (evalCentralised cName c).result
  ) contracts;

  peersFor = node: cName:
    if contracts.${cName}.handler == null
    then [ node ]
    else nodeNames;

  mkNode = node: {
    environment.etc = lib.listToAttrs (lib.concatMap (cName:
      map (peer: lib.nameValuePair "contracts-explore/${cName}/${peer}" {
        text = lib.generators.toPretty { multiline = false; } resultsByContractByNode.${cName}.${peer};
      }) (peersFor node cName)
    ) (lib.attrNames contracts));
  };
in
{
  name = "contracts-microservice-explore-C";

  nodes = lib.genAttrs nodeNames mkNode;

  testScript =
    let
      expectedFor = node:
        lib.concatMap (cName:
          map (peer: {
            path = "/etc/contracts-explore/${cName}/${peer}";
            content = lib.generators.toPretty { multiline = false; } resultsByContractByNode.${cName}.${peer};
          }) (peersFor node cName)
        ) (lib.attrNames contracts);

      pyDictFor = node:
        "{" + lib.concatMapStringsSep ", " (e:
          "${builtins.toJSON e.path}: ${builtins.toJSON e.content}"
        ) (expectedFor node) + "}";

      missingFor = node:
        lib.concatMap (cName:
          let allOthers = lib.subtractLists (peersFor node cName) nodeNames; in
          map (peer: "/etc/contracts-explore/${cName}/${peer}") allOthers
        ) (lib.attrNames contracts);

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
