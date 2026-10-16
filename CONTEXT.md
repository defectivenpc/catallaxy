# Catallaxy

Catallaxy builds Kubernetes clusters by composing floes. This file is the
language: what each word means here, and which near-synonym not to reach
for. The module-system vocabulary underneath it — signature, hole, link,
sealing, inclusion, export signature — belongs to the floe interface and is
defined in that repository's own `CONTEXT.md`.

Every word below is the word the tree uses. The retired ones are listed
because older notes and branches still carry them.

## A cluster

**Cluster**: A handle and its content, taken together. Neither the thing
that makes it nor the host it runs on. _Avoid_: target, environment, k8s

**Cluster handle**: What can be observed of a cluster that already exists:
its identity, version, node counts, networks, context. A field belongs here
if and only if it could be read off a cluster that exists. _Avoid_: claim,
descriptor, status, facts

**Provisioning**: What establishes a handle — which tool is driven, with
which arguments, and the hooks around it. For a cluster nobody here creates,
it is a retrieval: where to fetch the kubeconfig. _Avoid_: descriptor,
recipe, lifecycle, bootstrap

**Content**: The desired state of a cluster: every resource its components
render, with the partial order that installs them. _Avoid_: manifests,
payload, desired state, workloads

**Delivery**: How content reaches a claim — kapp, Argo CD, Fleet — and what
bootstraps whatever applies it. _Avoid_: deploy strategy, CD, apply method

## Composing one

**Component**: A floe installed into a cluster: it requires
`KUBERNETES_CLUSTER` and contributes what the cluster installs — content, or
the resources a state-based tool applies on its behalf. _Avoid_: chart floe,
member, app, addon

**Upstream**: The third-party artifact a component vendors, pinned in the
component's own `upstream.nix` — a Helm chart, a release file, a path in a
git tree. One upstream has one owner: the component that installs it, which
is also the only thing that may pin it. _Avoid_: chart, registry entry,
dependency, vendored chart

**Lab-scope floe**: A floe that is a unit of the lab's link rather than a
cluster's. It installs nothing into any cluster. What it does varies —
answer a signature, run a container on the host, fold its peers — so the
genus says only where it lives. _Avoid_: global floe, shared floe, lab
module

**Collector**: A lab-scope floe whose job is the fan-in: it `collects` what
its peers provide, owns the namespace it merges them into, and emits what
the container lowers. Every fan-in in the lab is one — a signature carries
the contributions when they stay distinct and keyed by who made them, an
output kind when they merge into one value. `lab-delivery` folds every
cluster's applier into one arrangement; `lab-dns` folds every exported
hostname into a zone. Being one is an axis, not a kind — `lab-dns` is also a
host floe. _Avoid_: aggregator, reducer, lab service

**Cluster floe**: A floe whose units are components and whose exports are
what crosses out of it. Written by hand, not assembled: its header states
what it needs of whatever places it and what it offers back, so its
interface is readable before anything evaluates. A lab's own live in that
lab's directory. _Avoid_: preset, platform, closure, stack

**Frame**: What every floe of a kind has whatever else its author declares:
a set of inputs and a list of policies. A cluster's is the two controls over
all of its namespaces; a lab's is the nine inputs every lab has. An author
may _refine_ a framed input — write a default and keep the frame's type and
prose — rather than redeclare it. _Avoid_: base, preset, defaults, mixin

**Cluster hole**: The `KUBERNETES_CLUSTER` a cluster floe leaves open,
written `requires.cluster` like any other hole on that signature. What makes
one definition serve k3d here and Talos elsewhere, because a component
resolves against the hole and never against the provisioner that fills it.
_Avoid_: claim hole, provisioner input, cluster unit

**Closed**: A cluster floe with no hole a lab would fill. Only a closed one
has content, so only a closed one is lowered. Its cluster hole is open even
so — what establishes a cluster is the provisioner beside it, which is not a
lab. _Avoid_: complete, resolved, concrete

**Open**: A cluster floe with a hole something outside it must fill.
Reusable and documented; never lowered on its own. _Avoid_: partial,
abstract, templated

**Host floe**: A lab-scope floe that provides a `HOST_SERVICE` — a container
the lab runs on the operator's machine rather than in any cluster. It
installs nothing; its _unit name_ is a CLI contract, because `lab-services`
keys the collection by it and that is the name of its state directory. A lab
runs one by placing it, so there is no `enable` to turn off. _Avoid_:
service module, sidecar, lab container

**Withdrawal**: An environment removing a unit its base lab placed, written
`units.<n> = null` where it is instantiated. The negation placement does not
otherwise have: a floe absent from the units is simply not there, and
"absent" cannot be said by adding something. The only reason the `units`
input admits null.

**Lab store**: A place on the operator's machine that holds values nothing
in a lab can mint — a sops file, a set of environment variables, or a vault
elsewhere. A floe providing `LAB_SECRET_STORE`, resolved by whatever reads
or writes it. _Avoid_: secret backend, vault, keystore

**Authored secret**: One secret a lab holds and the keys in it, written down
by a human or held by an external system. A floe providing `LAB_SECRET`,
which a projection resolves instead of naming — so a key no secret holds is
refused where it is read. _Avoid_: lab secret, managed secret, sealed secret

**Generated secret**: A value a floe mints for itself, in its own bundle,
publishing the coordinates on its provide. The other kind, and the reason
the one above says "authored": a random credential never passes through a
lab store, and asking for one there would put it in the manifest and in the
digest pinning it. _Avoid_: dynamic secret, runtime secret

**Cluster store**: The `ClusterSecretStore` a cluster reads values through,
pointing at the lab store behind it. A floe providing `SECRET_STORE`.
Cluster-scoped and not namespaced, because a value minted in one namespace
is usually read in another. Not shared between clusters — only the backend
is. _Avoid_: secret store, ESO store

**Projection**: An authored secret landed in a cluster as a Secret `cata`
fills from the store. The floe contributes the _position_ and no value, so
nothing secret-shaped reaches the Nix store. _Avoid_: sync, mirror,
injection

**Publication**: A Secret one cluster minted, written to a key in a lab
store for another cluster to read. The producer names the key and provides
it, and never learns who reads — which is why this and the next are two
floes rather than one relation. _Avoid_: push, export, share

**Subscription**: The other end: a cluster resolving a publication and
materialising its value as a Secret under a local name. It reads the
producer's own key off what it resolved, so there is no second derivation of
an address for the two sides to disagree about. _Avoid_: pull, import,
consumer

**Lab root**: The one certificate authority a lab holds: the ingress serves
from it and every cluster that resolves `LAB_CA` signs from it. One, because
two means two chains and a client trusting one rejects the other. _Avoid_:
lab CA cert, self-signed root, trust anchor

**Step condition**: What a floe says about _when_ its step runs, given that
it has no name for a cluster it is not in. `beforeClusters` and
`afterClusters` name a cluster token, and the lab expands each into one
anchor per cluster. The whole vocabulary, deliberately. _Avoid_: ordering
hint, dependency, hook

**Claim**, in the sense of a hostname: What a routed floe `provides` so the
thing that answers for the zone learns the name from the link rather than by
reading what rendered. _Avoid_: route registration, hostname declaration

**Lab**: A floe whose units are clusters, the claim that answers each, and
the floes the lab holds itself — so it closes clusters and holds what sits
between them: the host services, the lab stores, and the values one cluster
hands another. It exports nothing, because nothing links labs. _Avoid_:
environment, site, fleet, deployment

**Lab floe**: The definition a lab is an instance of, written with
`mkLabFloe` — which applies the lab frame and adds the units every lab
holds, exactly as `mkClusterFloe` applies the cluster frame one level down.
An author declares the inputs _their_ lab's environments may vary, so what
can differ between two environments is readable from the definition's
header. _Avoid_: lab module, lab template

**Environment**: One instantiation of a lab floe — `minimal.tls` is
`minimal { tls = true; }`. Not another word for lab: the lab floe is the
definition and an environment is one of its instances, the same relation a
cluster floe has to the clusters built from it. _Avoid_: variant, overlay,
profile

**Channel**: A way something crosses out of a lab to the lowering. There are
three — an output kind, the wiring, and which floe each unit instantiates —
and a unit's `provides` is not one of them, because a lab seals its units.
_Avoid_: output, hatch, escape

## Lowering one

**Lowering**: Turning a closed cluster floe into a document and a rendered
tree. _Avoid_: compiling, building

**Elaboration**: The step inside lowering that turns a link result into
bundles, edges and waves. _Avoid_: expansion, resolution

**Document**: The lowered cluster, as the one thing `cata` parses: the
handle, the provisioning, the content and the delivery, and nothing no
command reads. _Avoid_: spec, ClusterSpec, config, metadata

**Bundle**: A group of resources installed as one, and a node of the install
graph. _Avoid_: chart, release, manifest group

**Wave**: A set of bundles none of which waits on another. Computed, never
written. _Avoid_: stage, tier, phase

## Retired

**Claim**, in the sense of a cluster: A **cluster handle**. The word was
inverted for the audience — in Kubernetes a claim is a request for something
to be created, and this is the thing that already exists — and it named four
separate things: the handle, the hole (`requires.cluster`), the provisioner
that fills it, and a hostname, which is the one sense that keeps the word.

**Preset**: A cluster floe. Inclusion lives in the floe interface now, so
there is no second mechanism for it.

**Scope**: Gone, twice. A value from outside a cluster arrives as a unit of
its link or it does not arrive.

**Crossable**: An export signature. The boundary declares what crosses; no
table decides it. The narrow form is a `floe.project` of the full one, so
there is no twin to keep in step either — and a signature with nothing in it
for a peer to read says so itself with `mayExport = false`.

**Provision**, in the sense of one exposed upward: An export.

**`rootFromLab`**: An export and a hole. A cluster signs from the lab's root
when it resolves `LAB_CA`; there is no boolean to keep in step with
`lab.proxy.tls.enable`, and no `lab.proxy.tls.enable` either — a lab
terminates TLS when it holds a root.

**Edge mode**: Gone. Where a cluster is reachable is its provisioner's
`CLUSTER_EDGE`; whether this lab fronts it is said by whether the cluster
exports its `HOST_EXPOSURE`. There is no third value and nothing to keep in
step with the export.

**exports**: In use again, and it means an inclusion's re-export. The
outward surface of a single floe is still `provides`.
