# Exploration: same scenario as `microservice-explore-A.nix` -- three
# nodes, three heterogeneous contracts, two centralised and one local --
# but using ONE `lib.evalModules` PER CONTRACT (Variant B).
#
# Each contract gets its own isolated module-system evaluation. Per-node
# `want` declarations are factored through a small `perContract` helper
# so they're not literally duplicated across the three evals.
#
# The observable result is identical to Variant A. The trade-off is
# structural: stronger isolation (a malformed contract def cannot
# poison sibling evals) at the cost of an explicit per-contract eval
# loop and no implicit cross-contract chaining.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types;

  nodeNames = [ "alice" "bob" "carol" ];
  nodeIndex = name: lib.lists.findFirstIndex (n: n == name) (throw "unknown node ${name}") nodeNames;

  # Each contract is fully described by its want/result option types,
  # the per-node want values, the routing decision, and a `fulfill`.
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

  # Build one `lib.evalModules` call for a single contract: declares
  # only that contract's want/result options, includes every node's
  # want for it, and computes results via the contract's fulfill.
  perContract = cName: c:
    (lib.evalModules {
      modules = [
        {
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
        }
        ({ config, ... }: {
          ${cName} = {
            want = lib.genAttrs nodeNames c.wantFor;
            result =
              lib.mapAttrs (node: want: c.fulfill { inherit node want; }) config.${cName}.want;
          };
        })
      ];
    }).config.${cName};

  evaluated = lib.mapAttrs perContract contracts;

  peersFor = node: cName:
    if contracts.${cName}.handler == null
    then [ node ]
    else nodeNames;

  mkNode = node: {
    environment.etc = lib.listToAttrs (lib.concatMap (cName:
      map (peer: lib.nameValuePair "contracts-explore/${cName}/${peer}" {
        text = lib.generators.toPretty { multiline = false; } evaluated.${cName}.result.${peer};
      }) (peersFor node cName)
    ) (lib.attrNames contracts));
  };
in
{
  name = "contracts-microservice-explore-B";

  nodes = lib.genAttrs nodeNames mkNode;

  testScript =
    let
      expectedFor = node:
        lib.concatMap (cName:
          map (peer: {
            path = "/etc/contracts-explore/${cName}/${peer}";
            content = lib.generators.toPretty { multiline = false; } evaluated.${cName}.result.${peer};
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
