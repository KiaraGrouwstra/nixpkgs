# Micro-service-style contracts: variant comparison

Three test-local variants of the same scenario -- three nodes
(`alice`, `bob`, `carol`), three contracts with distinct field
shapes (`bool` / `int` / `str`), per-contract routing between
centralised (one handler) and local (per-node) -- exploring how
eval-time information exchange between nodes can be structured for
micro-service-shaped deployments.

All three produce identical observable behaviour. The diff is purely
in evaluation strategy.

## Variant A: one shared `evalModules` for everything

`microservice-explore-A.nix`

One `lib.evalModules` call sees every node's `want` for every
contract and runs every contract's `fulfill`. Each node bakes its
slice of the resulting `sharedEval` into `/etc`.

- **Pros**
  - Single source of truth; concern chaining is natural (one
    contract's `result` can feed another's `request` inside the same
    eval, just by reading `config.<other-contract>.result`).
  - Routing decisions are co-located with the topology in one
    `routes` attrset, easy to read.
  - Smallest amount of mechanism: one eval, one bake site.
- **Cons**
  - Every NixOS node's config depends on the full shared eval. If
    the eval gets big, every node pays the cost on every rebuild.
  - The "decentralised namespace" (each contract at its own top-level
    option, no `config.contracts.*` umbrella) is real at the option
    layer, but conceptually the eval is still one big composition.

## Variant B: one shared `evalModules` per contract

`microservice-explore-B.nix`

Three independent `lib.evalModules` calls, one per contract. Each
sees only that contract's options plus every node's want for it.
A small `perContract` helper carries the per-contract spec
(schema, `wantFor`, `handler`, `fulfill`) so the per-node want
declarations are not literally duplicated across evals.

- **Pros**
  - Per-contract isolation: a malformed contract definition cannot
    poison sibling evals.
  - Each contract's schema lives only with its own usage; types
    don't have to coexist in one shared option tree.
  - Adding/removing a contract touches a single attribute.
- **Cons**
  - Cross-contract chaining (if we ever want it) needs an explicit
    bridge between evals, since they don't share `config`.
  - All three evals still globally scope across all nodes, so the
    eval graph for a purely local contract is no smaller than for
    a centralised one.

## Variant C: one `evalModules` per routing scope

`microservice-explore-C.nix`

Centralised contracts: one shared eval each (handler-scope). Local
contracts: one tiny eval per node (host-scope). Conceptually closest
to a real micro-service deployment -- each centralised service has
its own deployment, local services run independently per host.

- **Pros**
  - Eval graph mirrors the deployment topology: a node only
    participates in the evals it genuinely depends on.
  - Local contracts shrink to per-node evals, so there is no
    pretend-cross-node coordination for them.
- **Cons**
  - Two distinct eval shapes to implement (`evalCentralised` vs
    `evalLocalOnNode`) rather than one uniform pattern.
  - Cross-contract chaining is still possible but only within a
    routing scope.

## Take-aways

- The eval-time-only test scaffold (`environment.etc."..."` baked
  from a `let`-bound eval, equality asserted across nodes) is
  enough to make cross-node consistency observable without any
  runtime micro-service machinery. All three variants share this
  bake-and-compare scaffold.
- The "decentralised top-level option per contract" namespace
  (no `config.contracts.*` umbrella) composes cleanly under all
  three strategies and doesn't force a particular evaluation shape.
- Single-eval (A) buys implicit chaining. Per-contract (B) buys
  type-locality. Per-scope (C) buys deployment-shape fidelity.
  A and B are similar enough in cost that the choice is one of
  taste; C is meaningfully different and only worth the extra
  mechanism if "local services don't see each other" is a
  property we want to enforce structurally rather than by
  convention.
