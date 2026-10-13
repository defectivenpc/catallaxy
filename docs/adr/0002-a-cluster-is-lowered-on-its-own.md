# A cluster is lowered on its own

Lowering is defined only on **closed** compositions: a cluster floe with an
unfilled hole has no content to fold, so it is a _component_ — reusable,
linkable, documented, never lowered — and a closed one is a _cluster_, with
a document `cata` can act on without a lab. A lab becomes exactly a thing
that closes clusters, by filling the holes they declare.

## Considered options

**The lab stays the unit of lowering**, with cluster-as-floe an internal
refactor and the CLI surface unmoved. Rejected because the test for whether
a cluster is a concept on its own — can `cata` stand one up given nothing
but its own document? — stays false, and every leak back to the lab stays
invisible. Under this decision each leak is a parse failure naming the
field.

**Open holes lower to runtime obligations** the CLI satisfies, so a partial
cluster is still an artifact. Rejected because it rebuilds in the CLI the
hand-written both-sides-agree checking that inclusion exists to delete.

## Consequences

Three features collapse into one mechanism, because all three are a parent
filling a hole: a secret one cluster mints and another reads, one Argo CD
serving several clusters, and one cluster provisioning another. The
`provisions` option, the `publish`/`subscribe` pair and the lab-wide
delivery lookup all go.

A cluster must now _say_ how it is applied: `DELIVERY_POLICY` gets no
default, so the absence of a provider is an unfilled hole rather than a
silent kapp, and "applied by kapp" is a floe.

The labs break in the meantime. They are marked with the existing
`lab.unstable` mechanism, whose table `nix/checks/self-contained.nix` pins,
so the bar stays green and what is down is a diff rather than a red run.

It needed one addition to the floe interface: an inclusion's inner `wiring`
exposed at the parent under path-qualified keys, since `elaborateCluster`
reads it to derive bundle edges and the parent dropped it. That is the floe
repository's ADR 0010, beside its 0006.
