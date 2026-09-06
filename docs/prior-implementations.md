# Prior implementations, and what they cost

The floe interface has been built three times. The third is
[RFC 0001](rfcs/0001-floes.md) — `lib/floe-core/` — and is what ships. The
first two, and everything written against them, lived in `old-floes/` until
they were deleted; this is what was worth keeping from them.

The code is in git. `git show cec7fdc^:old-floes/` reaches the mixin spike,
and the tree just before the deletion commit that removed the rest has all
of it. Nothing here needs it back; this file exists so nobody re-derives a
dead end from scratch.

## 1. A floe as a module declaring `options.floes.<name>`

The original. `lib/floe/default.nix` was a barrel re-exporting `floeOptions`
from `modules/lab/cluster/floe-options.nix`, and `modules/lab/` was the
whole lab and cluster option tree around it.

**Its structural problem.** A floe _declared_ the interface rather than
instantiating one, so `cluster/floe-options.nix` and `lab-floe-options.nix`
were two hand-copied interfaces at two scopes with six channels identical
between them. Aggregation was six different merge mechanisms across eleven
channels — `mkMerge` for `bundles`, `//` with name-prefixing for
`lint`/`verify`, and a `length == 1` filter that **silently dropped** a
contested capability.

That last one is the whole argument for exactly-one-provider being a
_refusal_. A rule that silently picks is a rule nobody can debug.

## 2. The ML-style mixin spike

A floe as an _instance_ of a type, modelled on nixpkgs 25.11 Modular
Services: a portable base plus per-scope extensions, with the core written
once against the interface. Six files — `interface`, `registry`, `cluster`,
`lab`, `fold`, `wiring` — three test suites, and several floes ported to see
what the interface cost an author. **No port was ever registered, so none of
it shipped.**

**Worth knowing before re-deriving it.**

- `importApply` rather than `specialArgs` for framework values.
  `submoduleWith` _throws_ when two declarations of an option supply
  overlapping specialArgs, so a framework whose extension point is
  specialArgs cannot be extended downstream at all.
- Extensions do not inherit down the tree. `childExtensions` is separate,
  and one line of it is the whole scope hierarchy.
- `wiring.nix` threw rather than asserting, because the error it replaces —
  a missing attribute — is not catchable by `builtins.tryEval` at all. That
  is still why `lib/floe-core/link.nix` throws.

**Where it fell down.** `collectChannel` returned an `mkMerge`: a
_definition_, not a value. It had no join of its own, no identity to name,
and its associativity was the module system's rather than the fold's.
`lib/floe-catallaxy/component.nix` is the answer — a real monoid over
unit-qualified keys, whose laws are asserted in
`lib/tests/floe-cluster.nix`. And nothing in the spike ever rendered:
`mkRegistryModule` appeared only in tests, so "rendering is a pure function
of bundle data" stayed an argument rather than a fact.

## What was carried forward rather than rewritten

Not everything under the parked tree belonged to the old floe. These are
domain infrastructure, and the new implementation uses them unchanged:

| Now                                   | Was                                                                   |
| ------------------------------------- | --------------------------------------------------------------------- |
| `lib/kubernetes/`                     | `modules/lab/cluster/lib/kubernetes/` — generated K8s and CRD schemas |
| `lib/verify-types.nix`                | `modules/lab/verify-types.nix`                                        |
| a subset of `lib/{eval,render,util}/` | the graph algorithms, the bundle renderer, the readiness-probe DSL    |

`lib/eval/{graph,manifest-graph,manifest-autoedges}.nix` in particular are
read _unchanged_ by `lib/floe-catallaxy/elaborate.nix`: the elaborator
lowers onto the token vocabulary they already understand, which is why the
new implementation derives install order without reimplementing a
topological sort.

`cli/` was never parked. Its contract —
`legacyPackages.<system>.labs."<lab>"` and `labPackages."<lab>"` — is
unchanged across all three implementations.

## What has not been rebuilt

The parked tree was deleted with these still missing. They are features, not
interface, and each would be written against RFC 0001 rather than ported:

- **Cloud provisioning.** The `cluster-api` and `crossplane` floes and the
  `infra` lab.

  `minimal.talos` is back: `floes/provisioners/` has `k3d-cluster` and
  `talos-cluster`, and `catallaxy.cluster` carries a tagged union rather
  than a required k3d block, so a third is an ordinary addition (RFC 0005
  §6.4 and §8.2).

  RFC 0003's `resources` category is built and drives OpenTofu, so
  `infra-{plan,apply,destroy}` are emitted and no longer orphaned —
  `examples/labs/tests/every-floe.nix` renders a stack and
  `lib/tests/render-infra.nix` pins what the renderer does with it. The
  category is exercised entirely on providers that reach no network
  (`local`, `random`), which is what makes it iterable without an account.

  What remains orphaned is the Crossplane half: `pivot`,
  `release-cluster-cloud-resources` and
  `{reconcile,delete}-managed-resource` are shipped, implemented in the CLI,
  and **emitted by nothing**, because the channel that would emit them — a
  cluster declaring which _other_ clusters it brings into existence — does
  not exist yet. `bootstrap-argocd-helm`, `sync-kubeconfig`,
  `colima-network-route`, `host-trust-install` and `publish-images` are
  orphaned the same way.

- **The book.** `docs/` is `rfcs/` and this file. `pkgs/default.nix` has no
  docs target.

- **The out-of-tree consumer story.** `templates/consumer` and the
  `hello-floe` example — how someone writes a floe outside this repo.

- **A standalone `delivery` floe.** `DELIVERY_POLICY` has a consumer
  (`modules/lab/cd.nix`) and one producer (`argocd`). The floe that answered
  it with "kapp, no CD tool" is gone; `examples/labs/tests/every-floe.nix`
  records its absence deliberately.
