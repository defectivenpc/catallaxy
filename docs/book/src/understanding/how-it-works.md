# How It Works

Your configuration is evaluated by Nix into two things: an ordered plan, and
a tree of rendered manifests. A Rust CLI then executes them. Nothing is
computed at apply time.

```
your modules ──nix eval──> a plan + rendered manifests ──cata──> clusters
```

The consequence worth knowing up front is that everything is decided before
anything runs, so `cata lab plan` and `cata lab plan-manifests` show you the
whole decision without touching a cluster.

## The three layers

| Directory  | Is                                            | Public?                              |
| ---------- | --------------------------------------------- | ------------------------------------ |
| `floes/`   | the floes themselves, one directory each      | `floes/default.nix`                  |
| `modules/` | the option tree: everything a lab can declare | internal — configure through options |
| `lib/`     | the algorithms: linking, graphs, rendering    | internal                             |
| `cli/`     | `cata`: executes the plan                     | the CLI surface                      |

`cli/` is organised so that only `io/` talks to the outside world;
`domain/`, `plan/`, `lint/`, `codegen/` and `topology/` are pure, and
`commands/` is thin glue.

## The seam

Nix and Rust meet at exactly two commands:

```bash
nix eval  --json …#legacyPackages.<system>.labs."<lab>"          # what to do
nix build       …#legacyPackages.<system>.labPackages."<lab>"    # what to do it with
```

The first resolves to `lab.out.cliConfig` and is parsed once into a typed
`LabSpec`. The second resolves to `lab.out.package`: a store path holding
the rendered manifests, the lint checks, and every hook binary.

The CLI re-derives nothing. That is deliberate — Rust code deciding install
order would be a second source of truth for something the module system
already knows.

## Linking

Before any of that, a cluster's floes are **linked**: each `requires` is
matched to whatever `provides` that signature, and the resolved value is
handed to the requiring floe as `config.floe.requires.<hole>`. Exactly one
provider per signature — zero and two are both errors naming the floes
involved.

Linking is also where the value is **sealed**: a provide is checked against
its signature's fields, and anything else the provider attached is dropped.
So a consumer can only read what the signature promised, and a provider
cannot leak an implementation detail that consumers then quietly rely on.

The link result is what everything downstream reads. It carries the resolved
values _and_ the edges — which floe satisfied which hole — and those edges
are where install ordering comes from.

## Ordering: two graphs

Nothing carries a phase, a weight, or a number. Each node says what it needs
and what it offers, and the order is computed. There are two graphs, and
they share a vocabulary without sharing anything else:

|             | Install graph             | Plan graph         |
| ----------- | ------------------------- | ------------------ |
| orders      | bundles                   | steps              |
| within      | one cluster               | the whole lab      |
| declared at | `bundles.<name>`          | `lab.steps.<name>` |
| printed by  | `cata lab plan-manifests` | `cata lab plan`    |

### What an author writes, and what is derived

The install graph runs on tokens — `requires`, `provides` and `after` on
each bundle, where a token names a _state_ rather than a bundle, so
splitting or renaming the bundle that satisfies one breaks nothing. `after`
means "a later wave than that"; `requires` means "that must be **ready**
first". Applying a CRD and the CRD being usable are two different moments.

A floe author writes almost none of that. What a bundle declares is:

```nix
bundles.issuers = kinds.mkBundle {
  needs = [ "operator" ];                    # a SIBLING bundle in this floe
  ready = kinds.readyDeployment { … };       # how "ready" is decided
  resources = { … };
};
```

`needs` reaches only inside the floe. Everything crossing a floe boundary is
derived by the elaborator from the link graph: if this floe requires
`X509_ISSUANCE`, the edge to whatever provided it is already known and does
not need saying again. Some edges are derived structurally too — a
namespaced resource depends on whatever declares its namespace, a custom
resource on whatever declares its CRD.

This is the distinction that most repays knowing. A cross-floe `after`
string is not merely discouraged; it is not expressible, because a string
that happens to match is not a dependency anybody checked.

Bundles whose requirements are all met form a **wave** and install together.
Some edges are derived rather than written — a namespaced resource depends
on whatever declares its namespace, a custom resource on whatever declares
its CRD.

Steps work the same way, over the actions that are not applying a manifest:
creating a cluster, setting up host DNS, copying a Secret between clusters.
The CLI does one thing with them: `topoSort(steps)`, then execute in order.

## It fails at evaluation

The framework works hard to fail before anything reaches a cluster, because
a mistake costs more the later it is found. Roughly in order:

- **Types.** Every option is typed, and so are the Kubernetes resources,
  against schemas generated from upstream OpenAPI and CRDs.
- **Assertions.** Configuration that is well-typed but cannot work. The
  message comes from the floe author, who knows both the cause and the fix.
- **Graph contracts.** An anchor matching nothing, a `requires` nobody
  provides, or a cycle is an error naming the nodes involved.
- **`cata lab lint`.** Over the _rendered_ manifests, where cross-resource
  mistakes live — a Service selector matching no pods is valid YAML that
  applies cleanly and fails only when something tries to reach it.
- **Snapshots.** Plans are deterministic, so they are committed and diffed.
  A change that reorders three unrelated things is invisible in your diff
  and obvious in the snapshot's.

`nix flake check` runs all of these except lint's manifest tier, and none of
them needs a cluster.

## Where to look

- `floes/` — the floes, one directory each, registered in
  `floes/default.nix`. `floes/cluster/podinfo/` is the smallest complete
  one.
- `lib/floe-core/` — the primitive. `floe.nix` is `mkFloe`, `link.nix` is
  exactly-one-provider resolution and sealing, `types.nix` the type
  language.
- `lib/floe-catallaxy/` — this distribution on top of core: `component.nix`
  is the bundle schema, `elaborate.nix` turns a link result into a cluster
  picture, `render.nix` writes it out.
- `lib/eval/` — `manifest-graph.nix` and `plan-graph.nix` are the two sorts;
  `manifest-autoedges.nix` derives the structural edges.
- `lib/render/` — one file per delivery strategy over shared helpers.
- `modules/lab/` — the option tree. `out.nix` holds both seam artifacts.

## Next

- [Configure a Lab](../using/configuring.md)
- [Write a Floe](../using/writing-a-floe.md)
- [Contributing](../contributing.md): the development loop.
