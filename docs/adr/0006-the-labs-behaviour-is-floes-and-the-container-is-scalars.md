# The lab's behaviour is floes, and the container is scalars and lowering

Everything a lab _does_ is a floe. What is left in `modules/lab/` is the
deployer scalars, the per-cluster lifecycle steps, and the lowering — and
that is the whole of it, not a staging post.

Eleven lab-scope floes, where there were five:

| floe                              | what it is                                     |
| --------------------------------- | ---------------------------------------------- |
| `lab-network`                     | the docker network, and the steps that make it |
| `lab-zone`                        | the zone every cluster resolves against        |
| `lab-ca`                          | the one root, and `cert-generate`              |
| `lab-dns`                         | a resolver, collecting what it answers for     |
| `lab-proxy`                       | an ingress, collecting what it routes          |
| `lab-registry`                    | a pull-through cache, and its two steps        |
| `lab-egress`                      | a forward proxy                                |
| `lab-secret-store` / `lab-secret` | where authored values live                     |
| `lab-secrets`                     | collects the stores, emits `ensure-secrets`    |
| `lab-delivery`                    | collects the appliers, emits the handover      |

Four signatures and two output kinds carry what used to be threaded or
matched by string: `LAB_NETWORK`, `LAB_CA`, `catallaxy.labSteps`,
`catallaxy.cd`, with `LAB_SECRET_STORE` and `LAB_SECRET` from ADR 0005.

## A step is its own output

`catallaxy.labSteps` is the channel, and `modules/lab/steps.nix` the one
place that folds it. It was a `steps` field on `catallaxy.hostService`,
which made "this floe runs a container" and "this floe contributes a step"
one declaration when they are two — and left a floe that _only_ contributes
a step with no kind to emit.

A floe has no name for a cluster it is not in, so it states a condition and
the lab expands it: `beforeClusters` and `afterClusters`, each taking a
cluster token. That is the whole vocabulary on purpose. A floe that cannot
say what it means with those two should make the gap visible rather than
reach for an escape hatch that lets it say anything.

## What a collector is for

Three of the eleven answer no signature at all. `lab-secrets` and
`lab-delivery` exist to do a fan-in, and `lab-dns` and `lab-proxy` do one
besides running a container.

`lab-delivery` is the case that justifies the shape. Which applier a cluster
uses is that cluster's answer and `policies.oneDelivery` refuses a second;
the _arrangement_ — which cluster Argo runs on, which repository it reads,
what must be applied before it can apply — is one statement folded from what
the clusters said. `modules/lab/cd.nix` did that fold by walking every
cluster's exports and matching on signature name. `collects` is that walk,
declared.

And it is where the limit of "a floe has no name for a cluster" turns out to
be narrower than it reads: `lab-delivery`'s handover steps name a cluster,
and may, because the name is the **collection's key**. It is the cluster
that said it runs Argo, not one the floe went looking for. That is the
difference between a collection and a scan.

## Considered options

**The lab as a floe with a header.** Give `labLink` declared `requires`,
`provides` and `exports`. Rejected because nothing links labs, so the header
would be empty — and no mistake it would catch could be named.

**The lab as an authored floe with inputs**, one instantiation per
environment. ADR 0003 rejected this and the rejection stands: `homelab.mesh`
adds four floes per cluster that `homelab.local` does not have, so as inputs
that becomes `enableMesh = true` driving conditional units, which the model
refuses outright.

**A plain `mkLab { name, units, defaults }`.** Retired in ADR 0003 with the
measurement: a dozen of the ~47 remaining scalars derive from another, and
`docs/generated/options/` is `nixosOptionsDoc` over that tree.

## Consequences

**Three defects fell out, all of them live.**

`minimal.talos` ran a proxy — so the lab minted a root and HAProxy served
from it — with `cert-manager`'s `rootFromLab` defaulting false, so the
cluster minted a _second_ root over the Secret the CLI had already seeded.
Exactly what that option's own description warned about: two chains, a
client trusting one rejecting the other, nothing failing loudly enough to
say why. Its description also said "set it exactly when
`lab.proxy.tls.enable` is on", which is prose, and nobody had. `self-edge`
and `cloud` were in the same state. Four fixtures drop from three issuer
resources to one.

`lab.proxy.tls.enable` was set by no lab: it defaulted true and every proxy
lab took the default, so the TLS-off branch was untested at lab level. It is
deleted — a lab terminates TLS when it holds a root.

`lab.dns.server` was an option defaulting to `lab.network.gateway` that
nothing ever overrode. Gone with `LAB_NETWORK`.

**`LAB_NETWORK` came back, and the reason it was retired was still right.**
Two sessions ago nothing consumed it: the host floes took
`network = lab.name` from the module that owns `lab.name` and instantiates
them, which is the merge surface meeting the floe surface. Moving the
network steps created a floe that _is_ the network, and four floes taking
the address as a string while a fifth answers it is the asymmetry a
signature is for. Same facts, different tree — which is worth recording as
the shape of a decision that is allowed to change.

**Three gates could not move, and the reasons differ.** `setup-services` and
`remove-services` are statements about _all_ host services, and the
container owns that namespace — the keys are a CLI contract. The per-cluster
lifecycle names clusters. And `lab-network`'s `managed` had to become an
input rather than a placement condition: the old gate read the clusters'
lowered specs, and a unit of the link cannot be computed from that link's
lowering. It defaults true, and no plan snapshot moved, so the condition it
guarded has never fired in this tree.

**A singleton's provider needs no naming.** An optional hole is unwired
unless a deployer names the provider, and that rule is right — adding a floe
must not rewrite another floe's output behind your back. But a `singleton`
is one the linker already refuses a second of, so "which one" has exactly
one answer by construction. `modules/lab/types.nix` reads it off the units'
headers rather than six labs each writing `lab.defaults.LAB_CA = "ca"`
beside the line that places the CA.

**Placement stays the container's, and is not a smell.** `lab-registry` is
placed under `lab.registry.enable`; `lab-ca` is placed by the deployer. A
floe that exists emits its steps and answers its signature; whether it
exists is a decision, and `lab.*` options are where a decision merged across
`lab.nix` and `envs/*.nix` belongs. What moved out is the _behaviour_, which
was gated in one place and implemented in another.
