# The Model

A cluster is the unit. Everything else is either what goes in one or what
holds several.

```
Lab            a thing that closes clusters, and what sits between them
 └─ Cluster        a claim and its content
     └─ Component     one capability, installed into it
         └─ Bundle       resources that install together
```

Every option path and every error message sits somewhere in that stack.

## Cluster

A cluster **denotes** two things, and the pair is the whole of what it is:

- the **claim** — what can be observed of a cluster that already exists: its
  identity and context, its version, its node counts, its pod and service
  networks;
- the **content** — the desired state its components fold up to, as bundles
  with the partial order that installs them.

Two functions sit either side of the pair and are not part of it.
**Provisioning** is `Host → Claim`: which tool is driven, with which
arguments. **Delivery** is `(Claim, Content) → Plan`: how the content
reaches the claim, by kapp or by a CD tool that takes over. A cluster's
document carries all four, because `cata` is what applies the two functions
and has to be told which — but the cluster _is_ the pair.

The rule that places a field follows from that: **a field lives where the
thing it describes lives.** The operator's docker VM is `cata`
configuration, not a cluster's. Where a cluster is reached from is the
lab's, because a cluster that does not know it is in a lab cannot answer for
it. How long an apply may take belongs to whatever applies.

```bash
cata cluster up --from-file ./cluster.json
```

That needs no lab, no flake and no name to resolve. It is the test of
whether a cluster is a concept on its own, and a field that leaks back to
the lab fails it by name.

## Composition

A cluster is a **floe whose units are other floes** — Backpack's `include`,
and MixML's closure property: linking units yields a unit.

A floe may leave a hole open. A cluster with an open hole has no content to
fold, so **lowering is defined only on closed compositions**:

- an **open** cluster floe is a **component**: reusable, linkable,
  documented, never lowered;
- a **closed** one is a **cluster**: it has a claim and content, a document,
  and something that can act on it.

So a **lab** is exactly a thing that closes clusters. It links them as units
and fills the holes they declare, which is how three features turn out to be
one mechanism: a secret one cluster mints and another reads, one Argo CD
serving several clusters, and one cluster bringing another into existence.

```nix
app = mkClusterFloe {
  name = "app";
  requires.claim = sigs.KUBERNETES_CLUSTER;   # the hole a lab fills

  units = _: {
    kapp     = floes.kapp { };             # how content reaches it
    platform = floes.standard-cluster { }; # an assembly of components
    myapp    = floes.myapp { };            # and yours
  };
};
```

Three things about that block are decisions rather than accidents.

**A floe is instantiated, not enabled.** `floes.myapp { }` is a function
call and its result is an opaque value. There is no `enable`: a floe absent
from the attrset is simply not there, and if something needed what it
provided that is an error naming both.

**Nothing declares an ordering.** Nothing may. The order comes from the
signatures; [How It Works](./how-it-works.md) explains how.

**What crosses a boundary is declared.** An inclusion exports nothing by
default. A cluster names what another cluster may read, in the narrower form
the boundary allows, and the lab reads what it needs in order to lower a
cluster through that same mechanism rather than by reaching inside.

## Component

The unit of capability: a certificate manager, a gateway, your own
application. It requires `KUBERNETES_CLUSTER`, contributes to content, and
is a **type signature with an implementation behind it** — the signature
being the part you should be able to read on its own:

```nix
floe.mkFloe {
  name = "podinfo";
  summary = "podinfo, a small routed workload for proving a cluster serves traffic.";

  inputs = { /* what the deployer decides */ };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;   # what it needs, named by capability

  out.component = kinds.component;       # which kind it contributes

  modules = [ /* the body */ ];
}
```

`requires` and `provides` name **signatures**, not floes. `podinfo` requires
`API_GATEWAY`; it does not require `traefik`, and it never spells the
gateway's name, its namespace, its listener, or the lab's DNS zone.

Resolution is **exactly one provider per signature per cluster**. Zero is an
error naming what went unsatisfied; two is an error naming both.

## Bundle

A group of Kubernetes resources installed as a unit, written to
`bundles.<name>` inside a floe's component. Bundles are the nodes of the
install graph, which is why a floe usually emits several: a certificate
manager's CRDs, its operator and its issuers cannot install at the same
moment.

A bundle orders itself against its **siblings in the same floe**, with
`needs`. It cannot name another floe's bundle: ordering between floes comes
from the link graph, where it is checked, rather than from a string that
happens to match.

## What is checked about all this

Five laws, each with a check rather than a comment:

| Law              | Says                                                    | Checked by                                                |
| ---------------- | ------------------------------------------------------- | --------------------------------------------------------- |
| Compositionality | content is a monoid fold, and the algebra holds         | `lib/tests/floe-cluster.nix`                              |
| Sealing          | an inclusion is read through its exports and no further | `floes/tests/standard-cluster.nix`                        |
| Plan adequacy    | the plan is a function of the document and the tree     | the plan snapshots                                        |
| Tightness        | the document carries what is read, and only that        | `cli_parses_nothing_it_ignores`, `cluster-document-<lab>` |
| Cache agreement  | every derived view equals what the tree says            | `content-cache-<lab>-<cluster>`                           |

Tightness is the one that keeps finding things. A field parsed and never
fed, or emitted and never read, is invisible to every other check: it
renders, it digests, it passes. Five such fields came out when the
catch-alls hiding them went — among them a floe list whose namespaces were
guessed from unit names, and an enum variant no producer could emit.

## Where the words come from

The vocabulary is borrowed, not invented, and knowing the source explains
most of it at once. The floe interface is Haskell's
[Backpack](https://plv.mpi-sws.org/backpack/) — a mixin module system —
applied to NixOS modules rather than to Haskell modules, with ML's sealing.

| Here                        | There                                                                   |
| --------------------------- | ----------------------------------------------------------------------- |
| **Signature**               | a Backpack signature (`.hsig`): an interface with no implementation     |
| **Hole**                    | a hole: an unfilled signature a unit requires                           |
| **Link**                    | mixin linking: matching requirements to implementations by name         |
| **`requires` / `provides`** | a unit's requirements and provisions                                    |
| **Instantiation**           | instantiating a unit by filling its holes                               |
| **Inclusion**               | `include`: a unit whose body is a link of other units                   |
| **Sealing**                 | ML's opaque sealing (`:>`): a structure seen only through its signature |
| **Closure**                 | MixML's result that linking units yields a unit                         |

That correspondence is why the rules are what they are. A hole must be
filled by exactly one provider because mixin linking resolves by name, not
by search. A provided value is sealed because a signature is the _whole_
interface — if a consumer could read past it, the signature would not be
one. And a cluster is a unit, which is why a lab can link one.

Two places the analogy is bent, both recorded in the floe interface's ADRs:
an inclusion's holes are **declared rather than inferred**, because a floe's
interface has to be readable from its header before anything evaluates; and
**nothing is exported by default**, which is ML rather than Backpack, on the
grounds that what crosses a cluster boundary should be a decision.

## Next

- [How It Works](./how-it-works.md): how a declaration becomes a cluster.
- [Reuse a Cluster](../using/cluster-floes.md): assemblies, and what nesting
  changes.
- [Configure a Lab](../using/configuring.md): doing it.
