# A fan-in is a collector, and a signature carries it

Every fan-in in the lab is a floe. `modules/lab/` held four: the host
services, the plan steps, the secret stores and the secrets. Each is now a
collector floe over a signature, and what the container reads is one
emission per collector.

The rule that decided all of them:

> **A signature when the contributions stay distinct and keyed by who made
> them. An output kind when they merge into one value.**

| fan-in                   | was                              | is                                 |
| ------------------------ | -------------------------------- | ---------------------------------- |
| host services            | `catallaxy.hostService` ×4       | `HOST_SERVICE` → `lab-services`    |
| plan steps               | `catallaxy.labSteps` ×6          | `LAB_STEPS` → `lab-steps`          |
| stores and secrets       | two kinds, read by `secrets.nix` | widened signatures → `lab-secrets` |
| the component monoid ×37 | `catallaxy.component`            | unchanged                          |

The monoid is the case the rule keeps as an output kind, and it is why the
rule is not "signatures for everything": its contributions genuinely merge —
qualified, joined into bundles, ordered into waves — and a collection keyed
by contributor would have to be merged afterwards anyway.

## Why an output kind could not be the channel

`collects` collects signature providers. A floe cannot read its siblings'
`out`, so an output kind is folded by whoever holds the link — which meant
the fold could not be a unit of the thing it was folding. That is the whole
reason these four lived in the container; none of them was there because a
lab is not a floe.

The keys came out right for free. A collection is keyed by contributor, and
every one of these fan-ins wanted exactly that key: a host service's unit
name is what `cli/src/host/state.rs` keys its state directory by, and a
store's is what `cata secrets edit <store>` takes.
`modules/lab/host/default.nix` had a comment asserting that contract; it is
now how the mechanism works.

## One record at two widths

`lab-secret-store` provided a narrow `LAB_SECRET_STORE` for peers _and_
emitted a `catallaxy.labSecretStore` for the CLI. Collapsing them meant
widening the signature, which reads like a violation of "the signature in
`provides` is usually narrower than the one inside" — and is not. One record
wider than any single consumer is what `HOST_EXPOSURE` already is: `lab-dns`
reads its hosts and ignores its edge.

Two fields stopped being carried at all, both of them one fact written
twice. `direction` was `writable` worded for the CLI, emitted beside it,
with a test case asserting the two agreed; the collector derives it. And
`keys` meant two different sets — what a projection may read includes the
`ca.crt` and `ca.key` a `ca` secret holds without declaring either, while
what `cata` generates does not. Both are on the signature now, named apart,
from one expression.

## Cluster names are a collection too

`LAB_STEPS` looked blocked. A floe states _when_ it runs as a condition
(`beforeClusters = "created"`) because it has no name for a cluster it is
not in, and expanding that into one anchor per cluster needs the cluster
names — which `modules/lab/steps.nix` read off `config.lab.clusters`.

`KUBERNETES_CLUSTER` is provided by exactly three floes and all three are
claims, so a collection of it is keyed by `<cluster>-claim`.
`catallaxy.clusterOfClaimUnit` is the inverse of `claimUnitFor`, beside it,
so the convention stays one decision. Collected and not required, which is
also the right arity: a lab has any number of clusters including none, and
with none every condition expands to nothing.

## What the probe settled

A floe instance travels through `inputs` typed `attrsOf floeInstance`,
`units` reads it, and the inner unit lifts under the qualified name. So
"units cannot be inputs" was wrong, and with it the reason for a base
function per lab: there can be one `catallaxy.labFloe` that every lab and
every environment instantiates.

ADR 0006 rejected "the lab as an authored floe with inputs" because
`homelab.mesh` adds four floes per cluster and that would become
`enableMesh = true` driving conditional units. That rejection was about a
_boolean_. Units arriving as a value is not that — `mesh` passes a different
unit set and nothing branches.

## Consequences

**No manifest, plan, document or digest moved**, across all three
conversions. The fan-ins were behaviour-preserving by construction and the
snapshots are what proves it.

**Three assertions moved to where the thing they test lives.** `writable` is
pinned in the store floe's suite and `direction` in the collector's, because
that is where each is decided. A case asserting the two agreed is gone with
the duplication.

**The isolation harness refuses a `without` naming a stub that does not
exist.** `lab-delivery` asked for `without = [ "delivery" ]` against a stub
nobody had added, so three of its cases agreed with the case beside them and
the gitops handover was never exercised alone.

**What is left in `modules/lab/` is two things, not four.** The option
surface — 925 lines across `types.nix`, `host/` and `network/dns.nix`, which
exists to hold ~35 scalars and plumb them into floes that declare the same
inputs — and the lowering, ~1,700 lines that fold the component monoid into
documents and a plan. The first is deleted by moving the scalars to the
instantiation sites; the second is the fold a floe cannot do, and belongs
beside `elaborateCluster`.
