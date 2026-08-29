# old-floes

Two earlier floe implementations and everything written against them, kept
for reference. **Nothing in the main tree imports any of it, nothing builds
it, and it is not expected to evaluate.**

The platform is being re-architected on the third implementation —
`lib/floe-core/`, the interface of [RFC 0001](../docs/rfcs/0001-floes.md).
Until that grows a lab, `cata` has nothing to evaluate: there are no `labs`
or `labPackages` flake outputs. That is expected, not a regression.

Paths mirror where each file used to live, so provenance is readable and
imports _between_ parked files mostly still resolve. Imports reaching into
the live tree do not, and are not going to be fixed.

## What is here

### 1. The original floe interface — `lib/floe/`, `modules/`

A floe as a NixOS module declaring `options.floes.<name>` at a dynamic path.
`lib/floe/default.nix` was the `lib.floe` barrel that `lib/pure.nix`
exported as stable public API; `floeOptions` itself lived in
`modules/lab/cluster/floe-options.nix` and was re-exported. Around it,
`modules/lab/` is the whole lab and cluster option tree — planner,
provisioners, secrets, trust, network, ops, out.

Its structural problem: a floe _declares_ the interface rather than
instantiating one, so `modules/lab/cluster/floe-options.nix` and
`modules/lab/lab-floe-options.nix` are two hand-copied interfaces at two
scopes with six channels identical between them. Aggregation was six
different merge mechanisms across eleven channels — `mkMerge` for `bundles`,
`//` with name-prefixing for `lint`/`verify`, and a `length == 1` filter
that _silently drops_ a contested capability.

### 2. The ML-style mixin spike — `lib/floe/{interface,registry,cluster,lab,fold,wiring}.nix`

A floe as an _instance_ of a type, modelled on nixpkgs 25.11 Modular
Services: a portable base plus per-scope extensions, with the core
functionality written once against the interface.

| File                                                          | Was                                                                                                |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `interface.nix`                                               | the portable base, recursive via `options.floes`                                                   |
| `cluster.nix`, `lab.nix`                                      | the two scope extensions                                                                           |
| `registry.nix`                                                | `configure` in all but name — `extensions` for this scope, `childExtensions` for the next one down |
| `fold.nix`                                                    | tree walk, `collectAssertions`, `collectWarnings`, `collectChannel`, `foldChannels`                |
| `wiring.nix`                                                  | typed `dependencies`/`deps` resolved by capability                                                 |
| `floes/*/modular.nix`, `floes/lab/k3d-local-modular.nix`      | ports, to see what the interface cost an author                                                    |
| `lib/tests/floe-{typeclass,composition,port-equivalence}.nix` | 3 suites                                                                                           |

No port was ever registered in `floes/cluster/set.nix` or
`floes/lab/set.nix`, so none shipped.

**Worth reading before re-deriving it.** `importApply` rather than
`specialArgs` for framework values — `submoduleWith` _throws_ when two
declarations of an option supply overlapping specialArgs, so a framework
whose extension point is specialArgs cannot be extended downstream at all.
Extensions do not inherit down the tree; `childExtensions` is separate, and
one line of it is the whole scope hierarchy. And `wiring.nix` throws rather
than asserting, because the error it replaces — a missing attribute — is not
catchable by `builtins.tryEval` at all.

**Where it fell down.** `collectChannel` returns an `mkMerge`: a
_definition_, not a value. It has no join of its own, no identity to name,
and its associativity is the module system's rather than the fold's.
`lib/floe-catallaxy/component.nix` is the answer — a real monoid over
unit-qualified keys, whose laws are asserted in
`lib/tests/floe-cluster.nix`. And nothing in the spike ever rendered:
`mkRegistryModule` appeared only in tests, so "rendering is a pure function
of bundle data" stayed an argument.

### 3. Everything built on them

`floes/` (29 shipped floes, their isolation tests, the two lab floes),
`examples/` (the labs and the out-of-tree floe example), `templates/`,
`docs/book/`, `secrets/`, and the parts of `lib/`, `nix/checks/`, `pkgs/`
and `.github/workflows/` that exist only to evaluate or test a lab —
`labs.nix`, `lab-checks.nix`, `floe-checks/`, `pure.nix`, `contracts/`,
`infra/`, `docs/`, most of `eval/` and `render/`, the e2e runners.

## What stayed behind, and why

Not everything under a parked directory belonged to the old floe. Four
things were pulled out because the new implementation genuinely needs them
and they are domain infrastructure rather than floe interface:

| Stayed as                                     | Came from                                                             |
| --------------------------------------------- | --------------------------------------------------------------------- |
| `lib/kubernetes/`                             | `modules/lab/cluster/lib/kubernetes/` — generated K8s and CRD schemas |
| `lib/verify-types.nix`                        | `modules/lab/verify-types.nix`                                        |
| `staging/floes/lint/route-listener-exists.sh` | `floes/cluster/gateway/lint/`                                         |
| a subset of `lib/{eval,render,util}/`         | the graph algorithms, the bundle renderer, the readiness-probe DSL    |

`lib/eval/{graph,manifest-graph,manifest-autoedges}.nix` in particular are
reused _unchanged_ by `lib/floe-catallaxy/elaborate.nix`: the elaborator
lowers onto the token vocabulary they already read, which is why the new
implementation derives install order without reimplementing a topological
sort.

`cli/` is untouched. Its contract — `legacyPackages.<system>.labs."<lab>"`
and `labPackages."<lab>"` — is unchanged, and is the target `staging/` grows
back into.
