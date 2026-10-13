# A cluster is a claim and its content

A cluster denotes a pair: the **claim**, meaning whatever could be observed
of a cluster that already exists, and the **content**, meaning the desired
state its components fold up to. Provisioning (`Host → Claim`) and delivery
(`(Claim, Content) → Plan`) are the two functions either side of the pair
and are not part of it, which is why a cluster document carries them as
separate blocks rather than as fields of the cluster.

## Considered options

**One record of faces**, which is what `ClusterSpec` is today: identity,
existence, content, host, edge, exposure and obligations as a product of
seven. Rejected because three of those faces are facts about something that
is not the cluster — the operator's machine, the lab's routing — and nothing
in the shape says so, so each new field's placement is a matter of taste.

**One function**, `Host → World → World`: everything is the plan. Rejected
because equality becomes extensional over worlds, so no law about a cluster
is checkable.

## Consequences

The claim/provisioning boundary gets a criterion rather than a list: a field
is claim if and only if it could be observed from a cluster that exists.
`cli/src/domain/cluster_shape.rs` already runs that test for drift
detection, so the criterion is decidable by asking whether `cluster_shape`
could compare the field.

`provider` is deleted (the provisioning union's key already carries it) and
`assignsLoadBalancers` becomes an explicit claim field, with
`KUBERNETES_CLUSTER` understood as a narrower _view_ of the claim rather
than a second place the facts live.

Because content is a monoidal fold and the claim is the one thing not
folded, "exactly one component answers `KUBERNETES_CLUSTER`" stops being a
policy that runs after linking and becomes the shape of the denotation.

The laws, and where each is checked, are in
[The Model](../book/src/understanding/model.md).
