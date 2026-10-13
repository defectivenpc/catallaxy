# A lab is a link, and the host is a unit of it

A lab is one link whose units are authored floes: the clusters, the host
services, and the lab-scope floes that answer a fact the lab holds. Nothing
synthesizes a floe from an option tree. The module system keeps the one job
it is uniquely good at — the deployer-written scalars, merged across
`lab.nix` and `envs/*.nix` — and hands composition to the floe interface.

The complaint that started this was that `types.raw` felt like bastardizing
the module system. Measured, that was wrong: of 178 `mkOption` calls in
`modules/lab/`, 25 are `readOnly` lowering outputs on their way to
`cli/src/domain/`, ~85 are plan-step parameter schemas in plain attrsets
that are never `evalModules`'d, and ~60 are genuine deployer scalars. One
authoring-surface option was untyped (`lab.provides`, where
`lab.clusters.<c>.floes` next to it already used `catallaxy.floeInstance`).

The real defect was the other one. A cluster's signature was
**synthesized**: `openOf` derived `requires` by scanning the bag of floes,
`provides` and `exports` came from a `labReads` list plus the
`catallaxy.crossable` table, and arity was recovered afterwards by
`policies.oneCluster` and `policies.oneDelivery` counting what came out of
the link. `floes/lib/refusals.nix:175` says why that cannot stand: _"`units`
is a function of `inputs`, so the set of units inside is not known until
something evaluates, and a floe's interface has to be readable from its
header before anything does."_ A synthesized signature is one nobody can
read before evaluation, which is the single property floes exist to provide.

The host is a unit for a reason that is already visible as a defect:
`modules/lab/host/proxy.nix:32` and `modules/lab/network/dns.nix:34` fan in
over every cluster's `exposedHosts` with the same filter written twice, and
dns.nix's comment says so. That is `collects` done by hand — the
`networking.nix` shape from the floe interface's own NixOS example, where
one floe owns a namespace and its peers contribute claims to it. As
capabilities, a cluster states what it needs of a host and the link checks
it: the registry case that is prose today (`envs/talos.nix:43` disables it
because `registries.yaml` is bind-mounted and Talos takes machine config
instead) becomes a hole `talos-cluster` does not declare, refused by name.

## The interfaces

Five signatures carry everything the module tree used to carry by being one
fixpoint. The test each had to pass is that it replaces a fact two places
needed and nothing checked they agreed on.

| signature            | from           | to                     | replaces                                                  |
| -------------------- | -------------- | ---------------------- | --------------------------------------------------------- |
| `KUBERNETES_CLUSTER` | the claim      | every component        | — (exists)                                                |
| `DNS_ZONE`           | `lab-dns`      | clusters               | — (exists, via `floes/lab/zone.nix`)                      |
| `CNI_BOOTSTRAP`      | a CNI floe     | the claim              | `disableFlannel` + a hand-templated `autoDeployManifests` |
| `OCI_MIRROR`         | `lab-registry` | the claim              | `lab.registry.enable` and a `mkForce false` with a reason |
| `HOST_EXPOSURE`      | each cluster   | `lab-proxy`, `lab-dns` | `cluster.out.exposedHosts` read imperatively, twice       |
| `LAB_NETWORK`        | `lab-network`  | host floes, claims     | `lab.name` and `lab.network.{subnet,gateway}` threaded    |

> Not built, and the row overstated the problem. The only place a network
> fact travelled without an edge was the lab patching `network` into the k3d
> variant of a descriptor after the fact; `k3d-cluster` declares the input
> and placement fills it, beside `name` and `instanceName`. The host floes
> take it from the module that owns `lab.name` and instantiates them, which
> is the merge surface meeting the floe surface working as intended.

| `SECRET_STORE` | `lab-secrets` | projections | `source = "<name>"`
matching a string declared elsewhere |

`OCI_MIRROR` is new rather than `OCI_REGISTRY` reused: that one is an
in-cluster registry addressed by `namespace`, `url`, `pullRef` and
`credentials`, and a host mirror is neither in a cluster nor addressed that
way. It is `optional` on `k3d-cluster` and absent from `talos-cluster`,
which turns `envs/talos.nix` disabling the registry with an explanatory
paragraph into a hole the linker refuses by name.

> Built, with one correction: the linker does not refuse it. A provider
> nobody reads is not an error — only a _hole_ nobody fills is — so a Talos
> lab leaving the registry on would have run a cache consulted by nothing.
> The lab refuses it instead, reading the claims' headers and naming the
> provisioner that declares no hole. `envs/talos.nix` still turns it off,
> and the paragraph is now a sentence plus a mechanism.
>
> What `OCI_MIRROR` actually bought was on the Rust side. `create_cluster`
> joined `service_state_dir(lab, "registry")` from a literal and probed the
> filesystem with `.exists()`, so whether a cluster mirrored was decided at
> deploy by what happened to be on disk: a stale directory mounted a mirror
> nobody asked for, and a cluster whose `registry-setup` had not run mounted
> none and said nothing. The descriptor carries `nodeConfigFrom` now — the
> providing floe's unit name, which is its state directory — and a declared
> mirror whose file is missing is an error naming the step that writes it.
> It is in `ClusterShape` too, because it is a mount fixed at creation:
> turning the registry off leaves a running cluster whose nodes still pull
> through the old one.

`HOST_EXPOSURE` is one contribution per cluster carrying both the hostnames
and where to dial them —
`{ hosts = [{ host; bundle; tier; }]; edge = { mode; backend; httpPort; httpsPort; }; }`
— because the proxy and the resolver need the same two things and currently
each read them separately. The host side `collects` it, which is the
`networking.nix` shape, and the derived field is
`T.derivedFrom HOST_EXPOSURE` so a cluster cannot read back the routes it
contributed. `edge.mode` becomes an input on the cluster floe defaulting to
what its claim answered: the facts are the provisioner's, but _who fronts
this cluster_ is a decision, and `tests/self-edge.nix` overrides it. Putting
it on the host would reintroduce the keyed-by-cluster config this removes.

> Superseded by ADR 0004 on this point. `edge.mode` became no input at all:
> whether the lab fronts a cluster is said by whether that cluster exports
> its `HOST_EXPOSURE`, and the address travels inside that export as the
> provisioner's `CLUSTER_EDGE`. The shape above is otherwise what shipped.

One new output kind, `catallaxy.hostService = { service; steps; verify; }`,
rather than host floes emitting a `catallaxy.component` with no bundles. The
floe interface's own note on output schemas is the argument — "the schema
has no reason to be shared" — and a bundleless component would satisfy
`componentsTargetTheCluster` and `providersVerifyWhatTheyPromise` by
vacuity, which is how a host floe that forgot its probe would pass. Its keys
are a CLI contract rather than labels: `cli/src/host/state.rs` uses them as
state directory names and `create_cluster.rs` and `import_lab_ca` look up
`registry`, `dns` and `proxy` by literal string, so those stay the unit
names.

## Considered options

**Design the module better**: keep the submodule and tighten its types.
Rejected because the types were not the problem. `cluster.floes` is already
`attrsOf catallaxy.floeInstance`, every entry keeps the full floe check at
`instantiate` and at link, and no option type can make a header readable
that is computed from the bag it heads.

**A `CLUSTER_METADATA` signature** carrying the cluster's name and instance
name, so placement travels as a signature rather than through the `apply` on
`cluster.floes`. Rejected because `KUBERNETES_CLUSTER` already carries
`name`, `version` and `context`, and `link` already hands a floe its own
unit name. ADR 0001 refused a second place the facts live when it deleted
`provider`; this would reintroduce one. The fact that travels by neither is
the _lab's_ identity, so that is what gets a signature.

**The lab as an authored floe with inputs**, each environment a different
instantiation — the shape `examples/k8s` uses for its two clusters. Rejected
because environments differ by more than scalars: `homelab.mesh` adds four
floes per cluster that `homelab.local` does not have, so as inputs that
becomes `enableMesh = true` driving conditional units. The model page
refuses exactly that: _"A floe is instantiated, not enabled."_

**One link whose top unit is the host and whose units are labs**, which is
the honest model of a shared machine. Rejected because standing up one lab
would mean evaluating every lab on the host, and `lib/allocation.nix` exists
so that nobody chooses the numbers at all.

## Consequences

> Two of the decisions below were not taken, and both notes are inline where
> they belong: the flat `lab.units` and the plain `mkLab` are retired at the
> end of this section, and `LAB_NETWORK` is retired in **The interfaces**
> above. Everything else landed.

`lab.clusters.<c>` as a keyed submodule goes, and so does
`modules/lab/cluster/`. In its place a flat `lab.units`, holding cluster
floes, host floes and lab-scope floes side by side, as `examples/k8s`'s lab
does. `defaults` and `policies` are arguments to `floe.link`; assertions
ride the link result. `docs/generated/options/cluster.md` has nothing left
to generate, and the guidance moves into each cluster floe's header — which
is the point, since a header is readable and an option tree assembled from a
bag is not.

`openOf`, `labReads`, `catallaxy.crossable` and `policies.oneCluster`
delete. The claim's arity comes from resolution: a cluster declaring
`requires.claim = KUBERNETES_CLUSTER` gets zero-and-two refused by the
linker, naming the hole. This is the consequence ADR 0001 already recorded
and did not get: "exactly one component answers `KUBERNETES_CLUSTER`" stops
being a policy that runs after linking. It is also where `crossable` was
always going — `CONTEXT.md` has listed it under Retired since before this
was decided, because an authored boundary writes its own narrowed signature,
which is what `CLUSTER_SUMMARY` does in `examples/k8s`.

Two corrections to the above, found while mapping the change rather than
after shipping it.

**The claim's descriptor does not travel through its signature.**
`lib/floe-catallaxy/elaborate.nix` reads `out."catallaxy.cluster"` and
`slice.nix` narrows the lab's output to this cluster's own `<cluster>/`
keys, so a provisioner placed beside the cluster rather than inside it puts
its descriptor under its own name and the cluster's slice holds no cluster
at all. `KUBERNETES_CLUSTER` cannot carry it instead: it has the name,
version, context and subnets, and the descriptor additionally has the
provisioner's own block, its wait, its kube context and its instance name —
which is the claim/provisioning split ADR 0001 drew, so collapsing them
would undraw it. `sliceFor` therefore takes the unit that answered the claim
and includes its output. No new signature, and it reads the resolution that
already happened.

**`policies.oneDelivery` stays.** Resolution is exactly-one for a _hole_,
and delivery is not one: `kapp` is content, one per cluster, inside it. An
authored `provides.delivery` with `exports.delivery = "kapp/delivery"` makes
zero a refusal, because the linker rejects an export naming a unit that is
not there — but two delivery units inside are still only caught by a policy,
since nothing inside requires what they provide. The claim is the hole; the
delivery is not.

The stratification in `modules/lab/types.nix:159` — the lab's provides
cannot depend on any cluster, enforced by construction — is traded for
`T.derivedFrom`. It was already only half true, since the proxy and the
resolver both read every cluster's `exposedHosts`. Host and clusters depend
on each other mutually: the host needs the routes, the clusters need the
zone. That is a legal cycle and the same one the NixOS example runs between
`nginx` and `networking`; marking the derived field refuses a cluster
reading back its own contribution, from the headers, naming both floes. Per
field rather than per layer, and checked rather than asserted in a comment.

Pod Security Admission and the default-deny policies become cluster
_inputs_, not units. Namespaces already have an owner: a floe declares
`createNamespaces` on a bundle, `lib/floe-catallaxy/elaborate.nix:268`
aggregates them, and `orphaned` refuses a bundle installing into a namespace
nobody creates. The labels are a policy handed to that owner and applied
where the namespaces are made, so a namespace is never briefly open — and
`cluster/security.nix`'s own argument still holds: a floe declaring them
would be declaring them about its neighbours' namespaces.

`evalModules` leaves the lab path entirely, which is further than the
opening paragraph of this ADR claimed. Tracing all ~60 deployer options,
every one lands somewhere: the host scalars become their floe's inputs,
`lab.edges` goes (it did; the CLI reads a host map now), `lab.defaults` is
an argument to `floe.link`, `lab.assertions` rides the link result, and
`lab.out.*` is a fold over the link. So `mkLab` takes
`{ name, units, defaults }` and is a plain function.

What that gives up is cross-option defaults, and giving them up is the point
rather than the cost. `lab.dns.server` defaults from `lab.network.gateway`,
which derives from `lab.network.subnet` — the "six arguments a lab author
had to keep consistent, with nothing checking that they were" that
`floes/lab/zone.nix` was written to delete. `lab-dns` requires `LAB_NETWORK`
and reads the gateway off it. A fixpoint over one option tree becomes
resolution over declared interfaces, which is the same trade as every other
line of this document.

For an author it means `discoverLabs` stops merging modules: an environment
imports the base and overrides with `//` rather than `mkDefault`/`mkForce`.
That is affordable because every override in the tree is already a
whole-unit swap — the five `envs/*.nix` all replace the claim, and the two
that looked like component overrides were `standard-cluster` reassembled by
hand.

> **Retired.** Not built, and the three paragraphs above are wrong in a way
> worth keeping rather than deleting, because the reasoning reads well and
> the measurement is what refutes it.
>
> The claim that every override is a whole-unit swap is false. Of the ten
> `envs/*.nix`, five override a _deployer scalar_ their `lab.nix` set with
> `mkDefault`: `lab.proxy.enable`, `lab.registry.enable`, `lab.dns.enable`,
> `lab.verify.endpoints.enable`, `lab.secrets.envFile`. Those are affordable
> under `//` with `recursiveUpdate`, so on its own this only makes the
> authoring surface noisier.
>
> What kills it is the cross-option defaults, and the thing this ADR
> nominated to replace them. There are ~47 deployer scalars left and a dozen
> derive from another: `lab.dns.port` from `hostPort`, `lab.network.gateway`
> from `subnet`, four host ports from `lib/allocation.nix`, every container
> name from `lab.name`. The plan was that `lab-dns` would require
> `LAB_NETWORK` and read the gateway off it — and `LAB_NETWORK` is retired
> above, because the only fact that travelled without an edge was the k3d
> network and placement carries that now. With no signature to resolve them
> against, a plain `mkLab` reimplements option defaults by hand: a fixpoint
> over an attrset, with no types, no `defaultText`, and nothing to generate
> documentation from.
>
> That last one is concrete. `docs/generated/options/*.md` is
> `nixosOptionsDoc` over this tree, and `option-docs-check` and
> `option-descriptions` diff it — so a plain function deletes the authoring
> reference and two checks with it.
>
> And flattening `lab.clusters.<c>.{floe,claim}` into `lab.units` costs the
> one thing the submodule buys for free. Writing the claim _under_ its
> cluster is the whole of saying "this claim answers this cluster"; flat,
> that becomes a `<cluster>-claim` naming convention a deployer has to
> spell. ADRs 0004 and 0005 were spent removing exactly that kind of string
> pairing.
>
> So the opening paragraph of this ADR stands as written after all: the
> module system keeps the one job it is uniquely good at, and the
> measurement that was offered as evidence against it is the evidence for
> it. What the asymmetry between `lab.units` and `lab.clusters` actually
> cost was one silent failure — a name in both replaced rather than merged —
> and that is a throw at the link now, naming both sides.

The nine host steps `modules/lab/plan.nix` emits come through the channel
component floes already use, with `cluster` nullable on a contributed step
so a unit outside any cluster has a path. The gating disappears with the
booleans: `registry-setup` exists today because `hasRegistry` is true, which
stands in for "is there a registry floe in this lab", and a floe absent from
the attrset is simply not there. `docker-network-create` is the one that
improves most — gated today on
`hasServices || any onDockerNetwork clusterNames`, a condition over host
floes _and_ clusters, where a `lab-network` floe just emits it and a lab
without one has no network to make.

The subnet and host-port allocator stays outside the link. A link cannot see
another lab, so `PORT_CLAIM` catches two clusters in one lab colliding and
will never catch `minimal.local` and `minimal.tls` both wanting 80 and 443.
`lib/allocation.nix` keeps deciding by hash,
`examples/labs/tests/allocations.json` keeps being diff-checked, and its
output becomes the host floe's inputs rather than defaults on an option.
This is the reason the host floe is a unit of a lab and not the other way
round, and it is the thing to re-read before anyone reopens it.
