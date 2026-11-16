# Catallaxy: hierarchical labs, substrates and mappings

Nov 12, 2026 · @Michael

Both asks are the same move Catallaxy already made once: **turn an implicit
thing into a hole that a floe fills.** The claim hole made one cluster floe
serve k3d and Talos. Two more holes would do the same for the rest:

- **A management hole on a lab** (problem 1). A lab gets a narrow export, a
  management plane, and a child lab requires one. The hole can be filled by
  including the parent's floe (one flake, one link, one plan) or by a
  retrieval floe (separate repo, separate lifecycle), exactly as
  `k3d-cluster` and `external-cluster` both fill `KUBERNETES_CLUSTER`.
- **A host hole on whatever runs containers** (problem 2). Today "the
  operator's docker host" is implicit in `resolve_docker_host` and the
  allocation slot. Make it a lab-scope floe providing a container host, and
  localhost, a remote Docker engine and several hosts are just different
  fillers wired by the linker.

With both holes in place the hierarchy needs no bootstrap concept. **The
root of the tree is mapped to a realizer that runs outside any cluster**
(`cata` driving Talos, OpenTofu or kubeadm over SSH), and every level below
can use in-cluster realizers such as Cluster API or Crossplane. The local
Docker lab stays what it is: a lab mapped to a single host, valuable for
testing, with no bootstrap role.

The cost is one reversal: ADR 0007 says a lab exports nothing because
nothing links labs. Problem 1 is precisely a request for something to link
labs, so that ADR needs a successor rather than a workaround.

## What the tree already has

Most of the machinery exists; what is missing is a boundary above the lab
and a value for the host. Read from `main` today:

| Piece                                          | Where                                                                        | What it gives this design                                                       |
| ---------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Claim hole `KUBERNETES_CLUSTER`                | `lib/floe-catallaxy/sigs.nix`, `floes/provisioners/*`                        | The pattern to copy: one definition, many fillers                               |
| `CLUSTER_PROVISIONING` + `external-cluster`    | `examples/labs/tests/provisions.nix`, `lib/lower/plan-provisions.nix`        | Mgmt to workload inside one lab, with the apply-order edge derived              |
| Publication / subscription through a lab store | `examples/labs/tests/cloud.nix` (`doks` publishes, `kubeconfigKey` reads)    | A typed-by-key channel that already crosses a lifecycle boundary                |
| Environments of a lab floe                     | ADR 0010, `envs/*.nix`, withdrawal with `units.x = null`                     | Single-host and multi-host as two instances of one definition                   |
| Host floes (`HOST_SERVICE`, `LAB_NETWORK`)     | `floes/lab/*`, `cli/src/host/*`                                              | Registry, DNS, proxy, egress, CA: what runs beside clusters                     |
| Implicit docker host                           | `resolve_docker_host` in `cli/src/provision/mod.rs` (local socket or Colima) | The seam problem 2 replaces                                                     |
| One allocation slot per lab on a shared host   | `lib/allocation.nix`                                                         | Becomes per host once there is more than one                                    |
| `clusterctl move` adapter                      | `cli/src/io/clusterctl.rs` `move_all`, currently unused                      | Not needed by this design; useful only if a root ever self-hosts on Cluster API |
| Lab record                                     | `cli/src/domain/lab_record.rs`, `~/.local/share/catallaxy/labs`              | Local evidence of what a lab put on a machine; needs to say _which_ machine     |

Two items from `Review.md` intersect this directly: "cluster provisions
needs to go away. It is a hack that is hardcoding the idea of crossplane"
and "cluster edge needs to go away or be redesigned". Both are about the
same missing value (who manages a cluster, and where it is reached from), so
the design below tries to give them a home rather than patch them.

## Crossplane, in floe terms

Crossplane is converging on the right runtime shape (a pipeline of functions
from observed to desired state) while keeping its contracts as schemas,
which is the part floes already do better. The useful lesson is about
_runtime_ resolution, not authoring. (Crossplane details are from memory of
the v1.14 to v2 line, not re-checked today.)

| Crossplane                                       | Catallaxy equivalent                          | Gap it points at                                                                           |
| ------------------------------------------------ | --------------------------------------------- | ------------------------------------------------------------------------------------------ |
| XRD (a schema)                                   | Signature (fields plus who provides it)       | None; signatures carry arity and provenance, an XRD does not                               |
| Composition function pipeline                    | Elaboration into bundles and derived waves    | None at eval time                                                                          |
| References and selectors resolved in the cluster | Holes resolved by the linker at eval time     | Nothing resolves _across_ a lifecycle boundary yet; that is problem 1                      |
| Usage (deletion ordering)                        | `domain/teardown.rs`, plan reversal           | Teardown across labs, once labs link                                                       |
| Operations (one-shot day-2 tasks)                | Plan step kinds                               | None new: one-shot steps become actions in a saga                                          |
| v2 composes any Kubernetes resource              | `provisions-cluster` names any `resourceKind` | The mechanism (Crossplane, CAPI, tofu) is still a string, which is the Review.md complaint |

The YAML point in floe terms: Crossplane can only resolve a dependency when
both ends are running, so a missing provider is a stuck claim. Catallaxy
refuses it at link time naming both floes. Keeping that property is the test
for any cross-repo design: **a child lab whose parent cannot satisfy it
should fail at `nix eval`, not at reconcile**, even when the parent is in
another repo.

## Problem 1: parent and child labs, in separate repos

Yes, separate repos work, if the child requires the parent's **signature**
and the parent's **values** arrive through a filler. The signature is
checked at `nix eval` from a flake input; the values are retrieved at plan
time, the way `external-cluster` retrieves a kubeconfig today.

### The primitive: a management hole

```nix
# sigs.nix
MANAGEMENT_PLANE = floe.mkSig {
  name = "MANAGEMENT_PLANE";
  description = "A cluster that reconciles other clusters into existence, and how to reach it.";
  fields = {
    context = T.str;
    kubeconfigKey = T.str;
  };
};

# regional repo: a lab that exports one thing
regional = mkLabFloe {
  name = "regional";
  provides.management = sigs.MANAGEMENT_PLANE;
  exports.management = "mgmt/management";
  clusters = _: { mgmt = { floe = clusters.mgmt { }; }; };
};

# local-mgmt repo: a lab that does not know it has a parent
localMgmt = mkLabFloe {
  name = "local-mgmt";
  clusters = _: { mgmt = { floe = clusters.mgmt { }; }; };
};

# the parent dependency lives on the mapping, not the lab
mappings.underParent = mkMapping {
  requires.parent = sigs.MANAGEMENT_PLANE;
  cluster = { parent, ... }: _name: floes.managed-cluster { inherit parent; };
};

localMgmt.prod = localMgmt {
  mapping = mappings.underParent;
  parent  = floes.external-lab { key = "labs/regional/management"; };
};

localMgmt.dev = localMgmt {
  substrate = { here = floes.local-docker { }; };
  mapping   = mappings.singleHost;
};
```

`managed-cluster` would be the successor to `external-cluster` plus
`CLUSTER_PROVISIONING`: a claim that requires `MANAGEMENT_PLANE` and is a
retrieval; a mapping places it, so the lab never names it. That also answers
the Review.md note, because the mechanism becomes a floe in the management
cluster rather than a `resourceKind` string.

### Two fillers for the same hole

| Filler                              | How the child gets its parent                                                                                             | Lifecycle                                                             | Use when                                                               |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Inclusion: the parent lab is a unit | A region floe whose units are labs; `regional` is a flake input                                                           | One link, one plan for the whole tree; ordering across levels derived | You own every level and want one `lab plan` to show it all             |
| Retrieval: `floes.external-lab`     | Reads the parent's published `MANAGEMENT_PLANE` from a lab store key; the parent flake is an input only for its signature | Each lab planned and applied on its own                               | Different repos, owners or cadences; the common case for workload labs |

The child's definition is identical under both; only its environment
changes. That is the property the claim hole has, and it is what makes "same
lab, tested locally under one parent, deployed under another" free.

### Developing one lab at a time

Because the parent dependency is on the mapping, a child lab can be
developed with no parent in existence. What you need depends on what you
run:

| You run                                 | Parent hole                                                                           | Other lab-level holes from the parent |
| --------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------- |
| `nix eval`, `lab plan`, lint, snapshots | A stub floe taking the `MANAGEMENT_PLANE` fields as literal Nix data                  | Stubbed with literal data             |
| `lab up` locally                        | None: the dev environment uses `singleHost`, so `cata` realizes its clusters with k3d | Stubbed with literal data             |
| `lab up` against a real parent path     | A tiny local parent lab (k3d plus Cluster API's Docker provider)                      | Filled by that local parent           |

A lab-level hole stays for anything the child reads from its parent for its
own sake, not for being made: publishing its kubeconfig into the parent's
store, or a DNS delegation from the parent's zone. Those are plain data in
dev.

### Rules that keep it sound

1. **Dependencies point up.** A child's mapping names its parent's
   signature, and the lab itself stays parent-agnostic; a parent never
   enumerates children. Adding cluster C touches no regional file.
2. **Signatures are versioned with the flake lock.** The child pins the
   parent flake; a field the child reads that the parent no longer exports
   fails at eval, not at reconcile.
3. **Teardown checks down.** The one runtime check this adds: destroying a
   lab that provides `MANAGEMENT_PLANE` refuses while the management cluster
   still holds child objects. The parent cannot know children statically, so
   it asks the cluster.
4. **Values cross through a store, never through Nix.** Same rule as
   publication and subscription, so a kubeconfig never lands in the store
   path or a digest.

## Problem 2: the host as a hole

"The host" currently means three things that are the same machine only on a
laptop. Remote Docker separates the first from the second, and multiple
hosts multiply the second.

| Role                                                                      | Today                                         | Lives where once split                                          |
| ------------------------------------------------------------------------- | --------------------------------------------- | --------------------------------------------------------------- |
| Operator: where `cata` runs, sudo, trust store, host resolver, lab record | Implicit, `$HOME`                             | Stays local; the lab record gains which host each thing went to |
| Container engine: where k3d nodes and host services run                   | `resolve_docker_host`: local socket or Colima | A `CONTAINER_HOST` filler per engine                            |
| Edge: where a cluster's gateway is dialled from                           | `CLUSTER_EDGE`, `HOST_EXPOSURE`               | Derived from the host's address as the operator reaches it      |

### The primitive: a container host hole

```nix
CONTAINER_HOST = floe.mkSig {
  name = "CONTAINER_HOST";
  description = "A container engine the lab places clusters and host services on, as the operator reaches it.";
  fields = {
    endpoint = T.str;   # what DOCKER_HOST is set to
    address = T.str;    # where the operator dials published ports
  };
};

units = _: {
  here  = floes.local-docker { };                         # or floes.colima-host { }
  box1  = floes.ssh-docker-host { address = "10.0.0.11"; };
  box2  = floes.ssh-docker-host { address = "10.0.0.12"; };
};
```

`k3d-cluster` and every host floe require `CONTAINER_HOST`; with one host in
the lab the default wires it, with several the environment binds each
cluster to one. That is the same mechanism as
`defaults.CLUSTER_PROVISIONING = "mgmt"`, so **placement is wiring**, not a
new subsystem. Colima stops being a special case in `config.rs` and becomes
one filler. `lib/allocation.nix` keys its slot by `(host, lab)` instead of
lab.

Multiple hosts, in order of cost:

- **One cluster per host, each its own edge.** No cross-host pod network;
  clusters talk through gateways, which `CLUSTER_EDGE` already models.
  Recommended first.
- **Hosts joined by the mesh.** `MESH_NETWORK` and the netbird floes already
  exist; the mesh becomes how host services on box1 reach a cluster on box2.
- **One cluster's nodes spread over hosts.** Needs `talos-cluster` or a bare
  k3s filler on each host rather than k3d. Possible later without changing
  the hole.

### The root of the tree

No seed lab and no pivot. Every realizer runs in one of two places, and the
hierarchy only constrains the root:

| Where a realizer runs                 | Examples                                              | Can realize                   |
| ------------------------------------- | ----------------------------------------------------- | ----------------------------- |
| Outside any cluster, driven by `cata` | k3d, Talos via `talosctl`, OpenTofu, kubeadm over SSH | Anything, including the root  |
| Inside a management cluster           | Cluster API, Crossplane                               | Children of that cluster only |

So the regional management cluster is mapped to an out-of-cluster realizer,
and `cata` creates and upgrades it directly. Regional then runs in-cluster
realizers for local-mgmt, and local-mgmt for clusters A and B. A mapping
that puts the root on an in-cluster realizer is refused at link time,
because nothing above it provides `MANAGEMENT_PLANE`.

What this gives up: the root does not get Cluster API's rolling upgrades and
machine health checks, because nothing in-cluster manages it. Its lifecycle
is `cata` runs, from an operator machine or CI. If that ever changes, moving
the root to an in-cluster realizer is a change of mapping (see below), not a
new concept.

### Or: a dormant root lab

The alternative to `cata` realizing regional directly is to make the
hierarchy one level taller: a small **root lab**, mapped to a cheap
substrate (local Docker or a small VM), realized by `cata`, and down most of
the time. Regional becomes its child through `MANAGEMENT_PLANE` and is
realized in-cluster, the same way every level below is. The root rule still
holds; it just applies one level up.

It is a lab and not a cluster because a management cluster alone cannot
manage anything: it also needs the lab store its kubeconfigs and credentials
are published to, the lab root CA, and host services. A lab is exactly that
bundle, and all of it has to stay durable while the root is down. "Down most
of the time" is a lifecycle state, not a concept: `cata lab down` already
stops a lab and keeps its state.

|                                   | `cata` realizes regional                                    | Dormant root lab                                                     |
| --------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------- |
| How regional is made and upgraded | A `cata` realizer per platform (Talos, tofu, kubeadm)       | Cluster API, the same in-cluster realizer as every lower level       |
| Ownership state lives in          | The lab record and tofu state on the operator machine or CI | The root lab's cluster and store                                     |
| Extra thing to back up            | Nothing beyond the record                                   | The root lab: velero floe or etcd snapshots, or regional is orphaned |
| Auto-repair of regional           | Only when `cata` runs                                       | Only while the root is up                                            |
| Best when                         | No CAPI provider fits regional's platform                   | A CAPI provider exists for it (Proxmox, Hetzner, metal3, vSphere)    |

Both need no new concepts, so the design supports both and a deployment
picks one. Unlike the dropped seed environment, nothing is ever thrown away,
so nothing ever needs a pivot.

**Regional is not special.** It can run on any platform, like any other
cluster: local Docker, remote Docker, AWS, Google Cloud, Akamai, on-prem. So
the choice between the two columns is per deployment, made in the mapping,
and the root rule is the only constraint: whatever is at the top must be
mapped to an out-of-cluster realizer.

**Decided: `cata` is the default out-of-cluster realizer, and for now it
targets only local Docker and remote Docker** (k3d, and Talos-in-Docker).
Any other out-of-cluster realizer, such as the OpenTofu path behind today's
`doks` floe, sits behind the same `Realizer` interface rather than inside
`cata`'s core.

The consequence: a root mapped through `cata` lands on a Docker host, so the
dormant root lab is the default way to put regional on AWS, Google Cloud,
Akamai or on-prem. The root lab runs on local or remote Docker, and regional
is realized from it by the in-cluster provider for its platform. `cata`
realizing regional directly is the path when regional itself is on Docker.

### Where one lab ends and the next begins

Hierarchy exists at two scales with the same relation: cluster to cluster
inside one lab (today's `tests/provisions.nix`), and lab to lab across a
`MANAGEMENT_PLANE` hole, filled by retrieval (separate labs and plans) or
inclusion (literally nested in one plan). Split into separate labs where
**lifecycle, owner, repo or trust root differ**; keep one lab where they are
shared. The dormant root has its own lifecycle, so it is its own lab;
clusters A and B share everything, so they are one lab.

## One primitive at every level

&#91;embedded content: the hierarchy · root realized by cata, 3 clusters
below it, 3 repos\]

The root is the only place the design has an opinion about where a realizer
runs. Every arrow below it is the same thing, a filled management hole, and
a level never knows how the level above it was made.

## Mapping: from a lab's holes to a substrate

A mapping is an ML functor in floe terms: it requires a substrate's
signatures and provides the lab's open holes. Today every
`claim = floes.k3d-cluster { };` line is a hand-written mapping for one
cluster. The layer lifts those lines out of the lab into one named,
replaceable unit, and Cluster API, Crossplane, OpenTofu and k3d become
realizers that a mapping picks, never words a lab says.

| Layer     | What it says                                                   | Example                                                                    | Where it lives today               |
| --------- | -------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------- |
| Lab       | What exists, and which holes it leaves open                    | regional: a mgmt cluster, a registry, DNS                                  | `lab.nix`, minus the `claim` lines |
| Substrate | What is available to make things real                          | local Docker; box1 to box3 over SSH; a cloud account; a management cluster | Implicit in `resolve_docker_host`  |
| Mapping   | Which realizer fills each hole, on which part of the substrate | single host (the default); spread with `mgmt` on box1                      | `claim =` per cluster              |

```nix
mappings.singleHost = mkMapping {
  requires.host = sigs.CONTAINER_HOST;
  cluster  = { host, ... }: _name: floes.k3d-cluster { inherit host; };
  service  = { host, ... }: _name: host;
};

mappings.spread = { assign }: mkMapping {
  requires.hosts = sigs.CONTAINER_HOST;
  cluster = { hosts, ... }: name: floes.k3d-cluster { host = hosts.${assign.${name}}; };
  service = { hosts, ... }: name: hosts.${assign.${name}};
};

regional.local = regional {
  substrate = { here = floes.local-docker { }; };
  mapping   = mappings.singleHost;
};

regional.multi = regional {
  substrate = { box1 = floes.ssh-docker-host { address = "10.0.0.11"; };
                box2 = floes.ssh-docker-host { address = "10.0.0.12"; }; };
  mapping   = (mappings.spread { assign = { mgmt = "box1"; registry = "box2"; dns = "box2"; }; })
                .override { mgmt = floes.talos-cluster { }; };
};
```

What falls out:

1. **The lab is substrate-free.** No claim, host or mechanism in `lab.nix`.
   An environment becomes lab plus substrate plus mapping, which is the
   three things you listed.
2. **A default per substrate, overridable per unit.** A single local Docker
   host implies `singleHost`; an override replaces one unit's realizer the
   way withdrawal removes one unit.
3. **Total and checked.** A mapping that leaves a cluster unfilled, or
   overrides a unit the lab does not have, is refused at link time naming
   it.
4. **A management plane is a substrate.** Mapping a child lab onto
   regional's `MANAGEMENT_PLANE` means its clusters are realized there, by
   whatever realizer that mapping picks. So `MANAGEMENT_PLANE` drops its
   `mechanisms` field and the hierarchy needs no separate concept.
5. **Mappings stack.** A substrate can itself be a lab mapped onto something
   lower: hosts made by OpenTofu in a cloud account, then the lab mapped
   onto those hosts.
6. **Migration is a change of mapping.** Moving a lab to another substrate
   or realizer keeps the lab fixed; the plan is the difference between two
   realizations. It is an ordinary plan under the saga rules below, built
   when a real case needs it, not a primitive.

In Haskell terms the lab is a description over an abstract hole functor, and
a mapping is the interpreter (a natural transformation from holes to a
substrate's effects), so swapping it is swapping the interpretation, not
editing the program.

**Decided: a mapping is a plain Nix function**, applied by `mkLabFloe`
before linking. It turns a lab plus a substrate into a lab whose holes are
filled, and the linker then checks that result exactly as it checks a
hand-written lab today, so an unfilled cluster is still refused at eval.
This sidesteps the one awkward part of making it a floe: a floe has no name
for its siblings (ADR 0007), but a mapping must hand out values keyed by the
lab's unit names. What it gives up is a generated interface page per
mapping, which a doc comment on the function covers.

## What this does to `cata`

With every cluster, host service and cloud object reached through a
realizer, `cata` can drop most of its bespoke step kinds and run one loop:
**observe, diff (pure), act, repeat until observed matches desired or a
timeout**. `up`, `destroy` and `cleanup` become that loop pointed at
different targets, rather than three code paths.

```rust
pub trait Realizer {
    type Desired;
    type Observed;
    type Action;

    fn observe(&self, id: &Id) -> Result<Option<Self::Observed>>;
    fn diff(desired: Option<&Self::Desired>, observed: Option<&Self::Observed>) -> Vec<Self::Action>;
    fn act(&self, action: &Self::Action) -> Result<()>;
}
```

`diff` is pure and lives in `domain/`; `observe` and `act` are adapters in
`io/`. That is the hexagonal split CLAUDE.md asks for, applied to every
resource instead of only some. The k3d path already works this way:
`converge_existing_cluster`, `adopt_existing_cluster` and the `Fix` enum in
`provision/mod.rs` are observe, diff and act under other names. The proposal
is to make that the shape of everything.

| Today (27 step kinds, from `domain/step_kind.rs`)                                                                                                                                                                                              | Becomes                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Pairs split by direction: `CreateCluster`/`DestroyCluster`, `SetupServices`/`RemoveServices`, `DockerNetworkCreate`/`RemoveNetwork`, `DnsSetup`/`DnsTeardown`, `InfraApply`/`InfraDestroy`, `ReconcileManagedResource`/`DeleteManagedResource` | One resource kind each; teardown is desired = absent. `runs_in(Direction)` goes away                                           |
| Waits: `WaitForResources`, `WaitForClusterGone`, most of `ReleaseClusterCloudResources`                                                                                                                                                        | The loop's "until converged", with readiness owned by each realizer; one poll and timeout policy instead of per-step constants |
| `match ProvisionerKind { K3d, Talos, External }` in `provision/mod.rs` (837 lines)                                                                                                                                                             | One realizer per floe; Talos and external get the drift and adopt handling that only k3d has today                             |
| Crossplane-specific teardown: `delete_managed_resource`, `wait_for_cluster_gone`, `release_cluster_cloud_resources` (about 1,350 lines)                                                                                                        | The Crossplane realizer's `observe` and `act`; the Review.md "cluster provisions" hack has nowhere left to live                |
| `InfraPlan` / `InfraApply` / `InfraDestroy`                                                                                                                                                                                                    | The OpenTofu realizer: `tofu plan` is its `diff`                                                                               |
| `resolve_docker_host` and the Colima branch in `config.rs`                                                                                                                                                                                     | A substrate value handed to the realizer                                                                                       |
| `SyncKubeconfig`                                                                                                                                                                                                                               | Part of what a cluster realizer observes and publishes                                                                         |
| `lab cleanup` with its separate inventory model                                                                                                                                                                                                | The same loop toward empty, driven by the lab record instead of the flake                                                      |
| `lab plan` printing a static step list                                                                                                                                                                                                         | The static graph plus the live diff: what would actually change                                                                |

What stays a one-shot action, because it is not convergent: delivery
bootstraps (`ApplyRootApplication`, `BootstrapArgocdKubectlSsa`,
`BootstrapForgejoRepos`), `RunScript` as the escape hatch, and minting the
lab root. `DeployManifests` stays delegated to the delivery floe, since kapp
and Argo are already reconcilers. The line is: **`cata` reconciles what
makes things real; delivery reconciles content.**

The lab record changes role too. It becomes the last realized state per
substrate (the equivalent of tofu state), which is what lets `cleanup` work
without the flake.

Costs: plan snapshots become resource-graph snapshots plus diffs, so every
fixture under `tests/plan-snapshots` moves once. The 28 Nix `plan-kinds`
shrink to resource kinds and actions, and `step-kind-conformance` checks the
trait instead. And the loop has to handle a realizer that cannot observe (an
unreachable API), which `release_cluster_cloud_resources` handles ad hoc
today with `report_unreachable`.

## The action trait: sagas, not just steps

A run of actions is a saga, so the trait should encode the saga rule: **any
number of compensable actions, then at most one commit, then only retriable
actions.** Once the commit runs, the run can only roll forward; before it,
every completed action can be undone in reverse order. The plan can check
that shape in pure code before anything runs. (Saga literature calls the
commit a "pivot transaction"; renamed here to keep it apart from the dropped
bootstrap pivot.)

The repo already has the seed of this:
`Idempotency { Idempotent, OneShot, Destructive }` in `domain/plan.rs`, set
as a policy string per step. The proposal is to make it a property of the
action's type, so it can't be wrong.

```rust
pub trait Action {
    type Receipt: Serialize + DeserializeOwned;

    fn describe(&self) -> Description;
    fn guard(&self) -> Fingerprint;
}

pub trait Retriable: Action {}

pub trait Compensable: Action {
    type Undo: Retriable;
    fn undo(receipt: &Self::Receipt) -> Option<Self::Undo>;
}

pub trait Commit: Action {}

pub enum Outcome<R> {
    Done(R),
    Refused { observed: Fingerprint },
    Unknown,
}

pub struct Saga<C, K, R> {
    compensable: Vec<C>,
    commit: Option<K>,
    retriable: Vec<R>,
}
```

The properties each piece buys:

1. **Undo comes from the receipt, not the request.** `CreateCluster` that
   _adopted_ an existing cluster returns a receipt saying so, and its `undo`
   is `None`. Compensating from the request would delete a cluster we never
   made. `adopt_existing_cluster` is where that distinction already lives.
2. **An undo must be retriable.** `type Undo: Retriable` makes "a
   compensation that itself needs compensating" unrepresentable. If an undo
   cannot finish, the run stops and emits a rescue hint, which is what
   `teardown::report` and `rescue_hints` already do for destroy.
3. **The guard is optimistic concurrency.** `diff` decided on what it
   observed; `act` checks the fingerprint still holds and returns `Refused`
   if not. The loop then re-observes rather than acting on stale state.
4. **`Unknown` is a first-class outcome.** A timeout means "did it happen?",
   so the loop must observe before either retrying or compensating.
   `wait_for_cluster_gone::Outcome::CannotTell` is this case today, handled
   locally.
5. **Receipts are journaled before the next action.** Written to the lab
   record, so a crash mid-run still knows what to compensate, and `cleanup`
   works from the journal without the flake.
6. **The saga shape is a type.** `Saga` has three fields in order, so a
   compensable action after the commit cannot be written down.

How today's kinds map:

| Class       | Today         | Examples                                                         |
| ----------- | ------------- | ---------------------------------------------------------------- |
| Retriable   | `Idempotent`  | Setup services, DNS, ensure secrets, deploy manifests, all undos |
| Compensable | `OneShot`     | Create cluster (undo: destroy, unless adopted), create network   |
| Commit      | `Destructive` | Destroy a cluster, `InfraDestroy`, delete a managed resource     |

Commits are rare and visible: `lab plan` marks the one a plan contains, and
the operator sees that everything before it can still roll back. `destroy`
is the plan that is mostly commits, which is why it runs last and reports
rescue hints.

Open points:

- **Parallel waves.** Actions in one wave may complete in any order;
  compensation must follow the journal's completion order, not plan order.
- **Granularity.** An action can only be undone as a whole, so coarse
  actions ("bootstrap Argo") hide partial progress. Smaller actions
  compensate more precisely but journal more.
- **Roll back or roll forward by default?** For `up`, roll forward (retry
  until converged) is usually right and compensation is opt-in; for a plan
  with a commit, rolling back until the commit is the safer default.
- **Trait objects.** The associated types do not erase cleanly into `dyn`;
  in practice each realizer contributes an enum of its actions and the saga
  holds those.

## Recommendation

Add the mapping layer with two substrate signatures (`CONTAINER_HOST`,
`MANAGEMENT_PLANE`), move `cata` onto the realizer loop with saga actions,
and retire `CLUSTER_PROVISIONING` into `managed-cluster`. Each step below is
one ADR and leaves every existing plan snapshot byte-identical until it opts
in, which is how ADR 0007 proved itself.

1. **Mapping layer, one host.** `CONTAINER_HOST` with `local-docker` and
   `colima-host`; a `singleHost` default mapping; the `claim =` lines move
   out of labs. No snapshot moves for a one-host lab.
2. **Realizer loop, k3d first.** Lift `converge_existing_cluster`,
   `adopt_existing_cluster` and `Fix` into the trait, then Talos and
   external; fold step kinds into it one at a time.
3. **A remote host.** `ssh-docker-host`, a `spread` mapping, and the lab
   record naming each host.
4. **Management is a signature.** `MANAGEMENT_PLANE` plus `managed-cluster`,
   replacing `CLUSTER_PROVISIONING` and `provisions-cluster`; Cluster API
   and Crossplane become in-cluster realizers; the root rule is checked at
   link time.
5. **A lab may export.** Successor to ADR 0007: a lab's `provides` may hold
   `MANAGEMENT_PLANE` and nothing else to begin with. Inclusion filler
   first.
6. **Retrieval across repos.** `external-lab`, publishing the export to a
   lab store, and a consumer template with two flakes.
7. **More hosts.** One cluster per host first; mesh-joined hosts next;
   spread nodes only if a real need shows up.

What I'd avoid: a `parent = "regional";` string on a lab. It is the same
shape as the `resourceKind` string Review.md already calls a hack, one level
up.

## Open questions for Michael

These change the design rather than its details; my default guess is in
brackets.

- [x] **Is reversing ADR 0007 acceptable, or should labs stay sealed and
      link only through stores?** Sealed means problem 1 is retrieval-only
      and loses the whole-tree plan. \[Reverse it, narrowly: one exported
      signature\]
- [x] **Answered:** Cluster API, Crossplane, OpenTofu and Terraform are
      implementation details: realizers a mapping picks, never part of a
      signature.
- [x] **Answered:** no seed and no pivot. The root is realized by `cata` out
      of cluster and its lifecycle is `cata` runs; local-mgmt is managed by
      regional.
- [x] **Where do host services (DNS, registry, proxy, CA) run for a remote
      root: on the root's host, or with the operator?** The lab root has one
      home either way. \[On the root's host, placed by the mapping\]
- [x] **Multi-host: is one cluster per host enough for your labs?** \[Yes
      for now\]
- [x] **Who owns a child lab's lifecycle in the long run: `cata` on an
      operator machine, or controllers in the parent?** If controllers,
      retrieval leans toward a GitOps registry and the parent needs to run
      `cata`'s plan in-cluster. \[`cata` first\]
- [x] **Does the floe interface already allow a lab-of-labs inclusion, or
      does `mkLabFloe` need a sibling?** I read only this repo, not the floe
      interface's own. \[Needs a sibling, `mkRegionFloe` or similar\]
