# RFC 0003 — Resources: state-based provisioning

Status: **Implemented.** Scope: one of the delivery categories a floe can
declare. Depends on RFC 0001, sibling to RFC 0002 and RFC 0004.

> **What shipped.** `lib/floe-catallaxy/resources.nix` (the kinds),
> `lib/render/infra.nix` (stacks → `main.tf.json`), `lib/tofu-providers.nix`
> (provider pins read off the derivation, §10), `floes/cluster/provisioned/`
> (a fixture on providers that reach nothing) and `floes/cluster/doks/` (a
> real cloud cluster). Driven by `infra-{plan,apply,destroy}` from
> `modules/lab/plan.nix`; pinned by `lib/tests/render-infra.nix`.
>
> Corrections to the text below:
>
> - **`after-manifests` is gone.** §5's table and §6's teardown paragraph
>   still describe three phases; the implementation ships two.
>   `resources.nix` gives the reason — the only case §11.2 could name was a
>   DNS record for a running service, which external-dns already does from
>   inside the cluster. §11.2 is answered: no.
> - **§7's publication is not a Kubernetes handle.** It writes into a
>   `lab.secrets.stores` entry the lab already declares, and a cluster reads
>   it with the `secrets.subscribe` it already has — one addressing scheme
>   rather than two.
> - **§12.8 is met**, as of the change that made `infra-plan`
>   `dryRunSafe = false` and gated it on `--infra`. A plan is read-only but
>   not inert: it authenticates and calls the provider's API.
> - **§8 is not met.** `tofu plan` writes no `-out` and `tofu apply`
>   consumes no plan file, so what is applied is not provably what the plan
>   showed.
> - **§7's "destroying a stack un-publishes" is not met.** What a
>   publication wrote into a secret store outlives the stack.
> - **§6's backward-phase refusal is not built**; a cycle between stacks is
>   caught, but by the plan graph, naming steps rather than the resource and
>   output.

RFC 0002 covers the reconcile camp — manifests handed to Kubernetes, which
converges. This covers the state-based camp: plan against recorded state,
apply once, record what was made. RFC 0004 covers what the lab runs for
itself.

Terraform is the default implementation; OpenTofu and Pulumi are
alternatives, and nothing a floe writes should name any of them.

## 0. What this category supplies

This RFC describes the **resources** delivery category. RFC 0001 defines no
category-registration mechanism; a category is a different output kind on a
floe — here `catallaxy.resources`. The four parts:

| Part         | Is                                                                     |
| ------------ | ---------------------------------------------------------------------- |
| `memberType` | `provider`, `type`, `inputs`, `outputs`, `phase` (§3)                  |
| `target`     | the state file its stack keys to (§5)                                  |
| `done`       | the apply returned; there is no separate probe                         |
| `nodes`      | one node per stack, not per resource — the tool orders within one (§5) |

Note what is absent: no readiness predicate and no sibling ordering. The
tool being driven supplies both, and duplicating them would be
re-implementing its dependency graph on top of it.

## 1. Two camps

|                 | Reconcile (RFC 0002)                     | State-based (this RFC)                           |
| --------------- | ---------------------------------------- | ------------------------------------------------ |
| Model           | level-triggered, converge, retry forever | one-shot plan then apply                         |
| Record of truth | the cluster itself                       | a state file mapping declarations to what exists |
| Ordering        | emergent; our graph supplies it          | the tool's own DAG, within one state             |
| Identity        | name and namespace                       | an address in state                              |
| Deletion        | garbage collection by ownership          | explicit destroy, driven by state                |
| Drift           | a controller corrects it                 | detected at plan, never corrected                |

The second camp cannot be dissolved into the first, for one blunt reason:
**something has to create the cluster the controllers run in.** Before any
cluster exists there is no reconciler, no CRD, and nowhere to put a
credential.

It also cannot be dissolved into a script. The state file is what binds a
declaration to the thing it made: the provider can list what exists, but
nothing out there says which of those is the resource named here. That
mapping is what makes a second apply a no-op rather than a duplicate, and a
destroy possible at all.

## 2. When a resource instead of a bundle

The boundary is not "cloud things are resources". Crossplane and Cluster API
provision cloud things and are **bundles** — they are controllers, they
reconcile, and they live in the first camp.

> Use a resource only when nothing in a cluster can own the thing.

Three cases satisfy that, and nothing else does:

1. **No cluster exists yet.** The network, the machines, the managed control
   plane the rest of the lab runs on.
2. **The credential must not live in a cluster.** A registrar or billing
   account whose token you are unwilling to hand to a controller.
3. **The lifetime outlives every cluster.** A DNS zone or state bucket that
   survives tearing the lab down and standing it up again.

If none applies, it is a bundle.

### Overlap is resolved by signatures, not by taxonomy

A Cloudflare DNS record can be made by a Terraform resource, by a Crossplane
`Record`, or by external-dns. A managed Kubernetes cluster can be made by
Terraform or by Cluster API. Cataloguing which camp each belongs to does not
stop two of them running at once.

RFC 0001 already answers this. `dns-record` is a **signature**, and exactly
one floe provides it per instantiation (RFC 0001 §4.6). Whether that floe
implements it with a resource or with a bundle is its own business, and
enabling two providers is a link error naming both. The rule in this section
decides what a floe _author_ should reach for; the one-provider rule is what
stops a _lab_ running two.

## 3. What a resource declares

```nix
resources.zone = {
  provider = "cloudflare";
  type     = "cloudflare_zone";

  inputs = {
    zone = config.domain;
    plan = "free";
  };

  outputs = [ "id" "name_servers" ];

  phase = "before-clusters";
};
```

| Field      | Meaning                                                   |
| ---------- | --------------------------------------------------------- |
| `provider` | which provider reconciles it                              |
| `type`     | the resource type in that provider's vocabulary           |
| `inputs`   | its configuration; may contain deferred values (§4)       |
| `outputs`  | the outputs this resource publishes, **declared by name** |
| `phase`    | position relative to cluster lifecycle (§5)               |

**`outputs` is declared, not inferred**, and that is deliberate. A typo in a
consumer's reference fails at evaluation, naming the resource and the
output, rather than part-way through an apply that has already created
things.

## 4. Deferred values

A resource's output does not exist until apply. `resources.zone.out.id` is
therefore a value of a distinct type: **known to exist, not yet known**.

In RFC 0001 §3.1 terms it is an ordinary value whose type says deferred.
That gives it a typing rule rather than a convention:

| A deferred value may flow into | Because                                 |
| ------------------------------ | --------------------------------------- |
| another resource's `inputs`    | the tool interpolates it at apply       |
| a publication (§7)             | that is what turns it into a real value |

| It may **not** flow into    | Because                                                               |
| --------------------------- | --------------------------------------------------------------------- |
| a bundle's manifests        | a manifest is rendered at build time; there is nothing to interpolate |
| any value read before apply | it is not a string yet                                                |

The last row is the important one. The alternative — scanning rendered
output afterwards for values that leaked where they should not — catches the
same error later, in a place that cannot name the line that caused it, and
only in the parts of a manifest that are untyped. As a type it needs no
scan: a manifest field takes a string, a deferred value is not one, and the
mismatch is reported where it was written.

**A signature value may be deferred**, and the signature says which. That is
how a consumer knows, at link time, whether it can interpolate a value or
must publish it first.

```nix
provides.dns-zone = {
  values = {
    domain = config.domain;                 # known now
    zoneId = deferred (resources.zone.out.id);  # known after apply
  };
};
```

## 5. Stacks

A **stack** is one state file and one apply. Stacks are derived, never
named:

> `stack = (instantiation, phase)`

**Why derived.** Nobody should have to invent a global stack name and hope
two floes agree — that is the untyped shared namespace RFC 0001 spent its
length removing.

**Why the instantiation and not the definition.** One definition is
instantiated many times — once per cluster, once per environment (RFC 0001
§4.6). Keying on the definition would put two environments' resources in one
state file with colliding addresses, so each would plan to destroy the
other's.

**Why not the reference graph.** State is stateful. If membership were the
connected components of the reference graph, adding one reference would
merge two stacks — and the merged stack has empty state, so it plans to
create everything while the old states still hold the originals. Terraform
will not migrate between state files on its own. `(instantiation, phase)`
changes only when an author renames something or moves a resource's phase,
both visible edits.

**Why a floe.** It is the module boundary. A floe's resources are its own,
and crossing the boundary requires an explicit published output — the same
shape as `provides` and `uses` one level up.

**Phases.** Three positions relative to cluster lifecycle:

| Phase             | Runs                                   |
| ----------------- | -------------------------------------- |
| `before-clusters` | before any cluster is created          |
| `after-clusters`  | after clusters exist, before manifests |
| `after-manifests` | after manifests are applied            |

### Inside a stack, the tool already does the work

Terraform builds a dependency graph from references between resources and
applies independent ones concurrently. **We do not re-implement that.** A
floe's resources in one phase share a state file, get ordered correctly, and
run in parallel, for free.

Our graph is only needed _between_ stacks, where the tool cannot see.

## 6. Ordering

**Derived from references.** If a resource in stack A reads an output of a
resource in stack B, A's plan waits for B's apply. Nothing is declared; the
edge is read out of the references (a fold over what was written, not a list
someone maintains).

Note it is A's _plan_ that waits, not A's apply: rendering A's plan needs
B's recorded state.

**Cross-stack reads become remote state**, and the remote-state
configuration is built from the producer's own backend rather than restated.
A reference within one stack becomes direct interpolation.

**Refused at evaluation**: a reference to an unknown resource; a reference
to an output the target does not declare; a reference backwards in phase; a
cycle between stacks.

**Teardown reverses it.** A stack is destroyed after everything that reads
from it.

Teardown needs its ordering against the cluster lifecycle stated in the same
detail as deploy, phase by phase. A single anchor covering every phase
leaves an `after-manifests` stack unordered against manifest removal, and a
destroy step with no forward edge lands next to network teardown by accident
of the sort rather than by declaration. An accident that happens to be
correct is not an ordering constraint.

## 7. Publication: how a deferred value reaches a cluster

This is the join between the two camps, and it is the easiest thing in the
design to get wrong. The tempting shape is to send outputs to some external
store and let the cluster fetch them back — which quietly introduces a
second addressing scheme, understood by neither side, that nothing checks.

> A publication turns a deferred value into a **handle**.

```nix
resources.zone.publish.id = {
  as = k8s.secret "cloudflare-zone" "zoneId";
};

bundles.dns.install = k8s.resources {
  config = uses.external-dns.new "DNSConfig" {
    zoneIdFrom = resources.zone.publish.id.handle.secretKeyRef;
  };
};
```

The publication materialises a Kubernetes object and yields a handle to it.
From there it is an ordinary handle in the sense of RFC 0002 §7 — a bundle
references it, and everything that already works for handles works for this.

Three things follow, and each replaces a mechanism:

- **The ordering is automatic.** The bundle references the handle, so it
  follows the publication, which follows the apply. No hand-written bridge
  token between the two camps.
- **The precondition is checkable.** A handle names an object something
  produces; a publication is what produces this one.
- **There is one path, not two.** A value crosses from state-based
  provisioning into a cluster exactly one way.

**Destroying a stack un-publishes.** What a publication created is part of
what the stack made, and leaving it behind is the same class of error as
leaving a cloud resource behind.

## 8. Plan and apply

Two steps, and the plan must be an **artifact the apply consumes**.

```text
plan   -> render the stack, plan against recorded state, write the plan out
apply  -> apply that plan
```

Planning and then re-planning at apply time leaves a window in which the
world changed between what was reviewed and what ran. For a category whose
whole purpose is "decide first, then act", that window is the one thing
worth closing.

**A plan is not inert.** It needs credentials and it talks to a provider's
API. It is read-only, but it must not run under a flag that an operator
reads as "nothing will happen" — a dry run should not reach a cloud account.

**An apply is gated.** It creates and destroys real infrastructure, so it
runs only when explicitly asked for.

## 9. Backend abstraction

The floe-facing model — provider, type, inputs, outputs, deferred values,
phase — is common to Terraform, OpenTofu and Pulumi. All three are the same
category: declare desired resources, diff against recorded state, apply.

What is backend-specific is rendering: interpolation syntax, the shape of
the generated file, how remote state is addressed. That is one seam, below
the floe.

**One honest limit.** `provider = "cloudflare"` and
`type = "cloudflare_zone"` are the _Terraform registry's_ vocabulary. Pulumi
spells the same resource differently and bridges to that registry. The
structure is abstract; the names are borrowed from whichever ecosystem
defines the provider, and pretending otherwise would mean maintaining a
translation table for every provider in existence.

## 10. Requirements an implementation must meet

The design above leaves several things underdetermined that are nonetheless
not free choices. Each of these is load-bearing.

- **A deferred value is a first-class value with a type**, not a string with
  a sentinel in it. A floe must be able to declare one, export one on a
  signature, and pass one around, without any of those sites knowing how it
  will be rendered.
- **Outputs are declared, never inferred.** Inference means a typo becomes a
  reference to nothing, discovered mid-apply.
- **Ordering is derived from references in both directions** — apply order
  from the references themselves, destroy order from their reverse. Neither
  is declared, so neither can be forgotten.
- **Cross-stack reads are configured from the producer's own backend**,
  never restated. Two descriptions of where a state file lives will
  disagree.
- **Provider versions come from whatever pins the provider**, read rather
  than reassembled, so the pinned artifact and the declared version cannot
  diverge.
- **Credentials appear in neither the rendered file nor the state.** They
  are read from the environment the apply runs in. A rendered plan is a
  build artifact and state is frequently shared; neither is a place for a
  secret.
- **Provisioning state is stored apart from disposable lab state.** Deleting
  a lab's working files must not delete the only record of what was created
  in a cloud account — that does not delete the resources, it loses track of
  them.
- **Teardown refuses while state still records resources**, unless
  explicitly overridden.
- **Cycles and backward-phase references are refused at evaluation**, with
  messages naming the resource and the output rather than the stack.

## 11. Open questions

1. **Can `phase` be derived?** A resource that reads a cluster fact must
   follow the cluster; one the cluster reads must precede it. That suggests
   phase is a consequence of the reference graph across both camps rather
   than a declaration. Attractive, and a larger claim than this RFC makes.
2. **Does `after-manifests` earn its place?** The only concrete case is a
   DNS record pointing at a LoadBalancer address that exists only after
   apply — and external-dns already does exactly that, from inside the
   cluster, in the other camp.
3. **Blast radius.** `(floe, phase)` fixes stack granularity. A floe with a
   large or unusually risky resource set may want to split further, and no
   escape hatch is designed here. Any such hatch must keep membership
   stable.
4. **Two accounts, one provider.** Nothing here expresses "this resource
   goes in the production account, that one in staging". Provider aliasing
   is the conventional answer and it interacts with stack identity (§5),
   since two accounts are two blast radii and arguably two stacks.

## 12. How to evaluate this concept alone

1. A DNS zone that must exist before any cluster is a resource; a DNS record
   for a running service is a bundle — and the rule in §2 says which without
   appealing to taxonomy.
2. Two floes both providing `dns-record`, one via Terraform and one via
   external-dns, is a link error naming both.
3. A floe's resources in one phase share a state file, and their internal
   ordering is Terraform's problem, not ours.
4. Adding a reference between two resources never moves either between state
   files.
5. A resource output reaches a workload as a mounted Secret, and the
   workload's bundle is ordered after the apply without anyone writing an
   ordering token.
6. A deferred value written into a manifest field is rejected where it was
   written, naming the field.
7. Destroying a stack removes what its publications created.
8. A dry run reaches no cloud account.
9. What an apply applies is what the plan showed.
10. Nothing in a floe names Terraform, OpenTofu, or Pulumi.
