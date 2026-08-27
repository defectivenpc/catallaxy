# RFC 0002 — Bundles: what a floe installs

Status: **Draft** Scope: one of the delivery categories a floe can declare.
Depends on RFC 0001, sibling to RFC 0003 and RFC 0004.

RFC 0001 defines a floe as a component with holes that declares an interface
— `requires` and `provides`, which know nothing about how anything is
delivered — and what it delivers. This RFC defines `bundles`, the reconcile
camp: manifests handed to Kubernetes, which converges. RFC 0003 defines
`resources`, the state-based camp; RFC 0004 defines `appliances`, what the
lab runs for itself.

## 0. What this category supplies

This RFC **registers the `bundles` category** (RFC 0001 §6.4). Its four
parts:

| Part         | Is                                                             |
| ------------ | -------------------------------------------------------------- |
| `memberType` | `install`, `ready`, `needs`, and the operator surface (§2)     |
| `target`     | the cluster containing the floe that declared it               |
| `done`       | its readiness probe, plus its workloads having rolled out (§4) |
| `nodes`      | one node per bundle                                            |

## 1. Why a floe has parts

A floe could have been one installable thing. It is not, for three reasons
that come from Kubernetes rather than from the module system.

**Readiness has granularity.** cert-manager's CRDs are established before
its admission webhook accepts traffic, which is before its default issuer
can sign anything. "cert-manager is ready" is not one fact and cannot be one
probe.

**Ordering exists inside a component.** A CRD must exist before the custom
resource that uses it, even when the same author ships both. That ordering
is real, and it is nobody else's business.

**Ownership has granularity.** A cluster may apply part of a floe
imperatively during bootstrap and hand the rest to a GitOps controller
afterwards. The split runs through a floe, not between floes.

A bundle is the unit at which all three are decided: **the unit of apply, of
readiness, and of ownership.**

## 2. What a bundle declares

| Field     | Meaning                                       | Consumed by                    |
| --------- | --------------------------------------------- | ------------------------------ |
| `install` | the Kubernetes objects it puts in the cluster | the renderer                   |
| `ready`   | the predicate that decides it is live         | the apply loop, and `backedBy` |
| `needs`   | sibling bundles that must be ready first      | the install graph              |
| `ops`     | commands the human operator may invoke        | the lab's ops tool             |
| `lint`    | checks against its own rendered output        | `cata lab lint`                |
| `verify`  | checks against the live cluster, on demand    | `cata lab verify`              |

All six are Kubernetes-aware, which is why they live here and not on the
floe. That is what keeps `requires` and `provides` a pure module interface
(RFC 0001 §6).

```nix
bundles.core = {
  install = k8s.helm { chart = charts.harbor; };
  ready   = k8s.ready.deployment "harbor-core";
};

bundles.tls = {
  needs   = [ config.bundles.core ];
  install = k8s.resources { /* … */ };
};
```

## 3. `install`

Three shapes, and only three.

| Shape                          | Meaning                                          |
| ------------------------------ | ------------------------------------------------ |
| `k8s.helm { chart; values; }`  | a Helm chart rendered to manifests at build time |
| `k8s.resources { <name> = … }` | objects written directly in Nix                  |
| `k8s.manifests [ <path> ]`     | pre-rendered YAML, typically upstream CRDs       |

### Resource content is typed

Whatever shape `install` takes, the objects it produces are typed against
Kubernetes' own schemas, generated from the upstream API specifications and
the CRDs a floe installs. That is where a wrong field type is caught, and
where a field left unset acquires its default.

Two limits are worth stating rather than discovering. **Unknown fields are
not caught by shape alone** — a Kubernetes object schema admits fields it
does not describe, so a misspelling is a new key rather than an error, and
catching it needs a strict validation pass over rendered output. And **a
kind with no schema is unchecked**, which is not rare: plenty of built-in
kinds carry no structured spec at all. A kind whose schema is absent should
be refused rather than silently waved through, with an explicit escape for
the cases where that is intended.

### Helm is a template language, not a package manager

A chart is a _source of manifests_. It is rendered at build time and the
output joins the same graph as everything else. Helm's own lifecycle —
hooks, weights, release state — is deliberately not honoured.

This is not incidental. RFC 0001 §1 argues that hook weights are an ordering
mechanism nobody outside the chart can read, and that the proliferation of
such private mechanisms is the problem. Honouring them here would
reintroduce exactly that: a second ordering system, invisible to the graph,
that cannot be checked.

The consequence is worth stating plainly: a chart that relies on hook
ordering to be correct will not work unmodified. That ordering has to be
expressed as bundles and `needs`, where it can be seen.

## 4. `ready`

A bundle's readiness is a predicate written down statically and evaluated at
apply time. RFC 0001 §9 gives the rule it must obey — **inspect to confirm,
never to discover** — and this is the vocabulary for doing so.

| Probe          | Asks                                           |
| -------------- | ---------------------------------------------- |
| `condition`    | does this resource carry this status condition |
| `jsonpath`     | does this path on this resource have a value   |
| `exists`       | is this resource present at all                |
| `kubectl-wait` | delegate to `kubectl wait`                     |
| `http`         | does this endpoint answer                      |
| `tcp`          | does this port accept a connection             |
| `dns`          | does this name resolve                         |
| `script`       | escape hatch — an arbitrary command            |

**Two execution contexts.** `condition`, `jsonpath`, `exists` and
`kubectl-wait` run against the API server and can be evaluated from wherever
the CLI runs. `http`, `tcp` and `dns` ask about in-cluster reachability, so
they are lowered into a one-shot Pod. A probe that needs the lab CA to make
its request can only be one of the second group.

**A bundle with no probe is still gated** by its workloads rolling out. The
probe is _additive_: it asks a question rollout completion does not answer,
such as whether a webhook is actually serving. It is never a substitute for
the rollout wait.

**`script` is the admission of defeat.** It is present because some upstream
components expose no other signal, and every use of it is a place where the
component's own readiness contract (RFC 0001 §9) is unwritable. Prefer any
other probe.

## 5. `needs`

A bundle names sibling bundles it must follow:

```nix
bundles.tls.needs = [ config.bundles.core ];
```

**By reference, not by name in a global namespace.** This is the whole of
intra-floe ordering, and it removes a class of coordination token that the
signature model alone does not reach: `gateway/controller/ready` →
`gateway/public/ready` → `gateway/tls/ready` orders three bundles inside one
floe, and cert-manager, netbird, crossplane and cluster-api each have a
sequence of the same kind. None is a cross-floe fact and none belongs
anywhere another floe can see it.

`needs` is the only ordering primitive a bundle has. If more is ever wanted,
this is where it goes — but an edge to a sibling has so far been enough.

Ordering _between_ floes is not expressible here and must not be. It comes
from `requires` and `backedBy` (RFC 0001 §6.3, §7), which is what makes it
checkable.

## 6. Operator surface

`ops`, `lint` and `verify` belong to the **bundle** rather than the floe,
because that is where the locality is. An ops command targets a workload, a
verify check asserts about resources, a lint check reads manifests — all
three are declared beside the thing they are about, and can interpolate its
namespace, its workload names, and `uses.<signature>` for a peer's value.
Any other home restates facts the bundle already holds.

All three fold outward to the lab (RFC 0001 §8, third flow). None is part of
any signature.

`ops` are keyed by category then name, matching the
`<lab>-ops <category> <name>` invocation.

```nix
bundles.server = {
  install = k8s.resources {
    instance = uses.identity-operator.new "Instance" { name = config.instanceName; };
  };

  ready = k8s.ready.statefulset config.instanceName;

  ops.identity.reset-admin = {
    description = "Recover the kanidm admin credential";
    command = [
      "kubectl" "-n" config.namespace
      "exec" "statefulset/${config.instanceName}" "--"
      "kanidmd" "recover-account" "admin"
    ];
  };

  ops.identity.check-oidc = {
    description = "Fetch the OIDC discovery document through the gateway";
    command = [
      "curl" "-sS"
      "--cacert" uses.trust-bundle.values.caBundle.mountPath
      "https://${config.domain}/oauth2/openid/.well-known/openid-configuration"
    ];
  };

  verify.admin-credential-valid = {
    description = "The admin credential still authenticates";
    probe = k8s.ready.http "https://${config.domain}/v1/auth" { expect = 200; };
  };
};
```

Both commands interpolate facts the bundle already holds — its namespace,
its StatefulSet name, its domain — and the second reads a peer's value
through a declared requirement. Neither spells a string that lives somewhere
else.

The `verify` check is the instructive one. A self-healing CronJob that
probes an endpoint and deletes a Secret when it fails is, under RFC 0001 §9,
a provider failing its own readiness contract with the blame hidden. The
check belongs here, naming the failure, rather than in a job that papers
over it.

**A check about consumers is not a bundle's check.** Some lints assert about
_other floes'_ output — "every route in this cluster attaches to a listener
some Gateway declares" examines everyone's routes, not the declaring floe's.
Nesting that on a bundle records where it was written rather than what it
examines. It is a signature lint (RFC 0001 §5.5). A bundle's `lint` is about
that bundle's own rendered output.

## 7. What a bundle exposes upward

A provision in RFC 0001 §5 is made of types and values, and both are
ultimately backed by something a bundle installs. Two constructors join the
two RFCs:

| Constructor                      | Produces                                      |
| -------------------------------- | --------------------------------------------- |
| `<bundle>.ref "<Kind>" "<name>"` | a value of reference type — a _handle_        |
| `<bundle>.crd "<group>/<Kind>"`  | a type member, defined by a CRD this installs |

```nix
provides.certificate-issuance = {
  types.Certificate = config.bundles.crds.crd "cert-manager.io/Certificate";
  values.defaultIssuer = config.bundles.issuers.ref "ClusterIssuer" "lab-ca";
  backedBy = [ config.bundles.issuers ];
};
```

Naming the bundle is what makes the claim checkable. A handle must name an
object that bundle actually renders, and a type must be defined by a CRD it
actually installs. Both are conformance checks over rendered output (RFC
0001 §17.4), and both are how a declaration is prevented from lying.

`backedBy` is separate and means something else: which bundles must be
_ready_ before a consumer may proceed. See RFC 0001 §6.3.

## 8. Elaboration

Linking produces the delivery graph (RFC 0001 §12), in which a bundle is one
node kind. This is what happens to the bundle nodes.

```text
delivery graph
  ->  bundle nodes      each carrying the cluster it targets
                        edges: `needs` within a floe,
                               a provider's `backedBy` -> each requirer,
                               plus derived structural edges
  ->  topological sort
  ->  waves             each wave a set with no edges among its members
  ->  apply             per wave, per cluster: render, apply, await rollout,
                        await probes
```

**A bundle node carries its target cluster**, supplied by the floe that
contains it (RFC 0001 §6.1). Two clusters in one lab put their bundles in
one graph, and each node says where it goes.

**Derived structural edges** are the ones nobody should have to write: a
namespaced object follows whoever declares the namespace; an object follows
whoever provides the Secret it mounts. These are read out of the rendered
output rather than declared. The CRD edge used to be derived this way too
and is now a declared type member (RFC 0001 §5.4), which is strictly better
— it cannot be forgotten and it carries a name.

**Waves are an artifact of the sort, not a concept.** They exist because
applying independent bundles concurrently is faster than applying them one
at a time. Nothing should ever reference a wave index, and a wave number is
not a place to encode ordering — that is the ArgoCD sync-wave mistake RFC
0001 §1 catalogues.

## 9. Open questions

1. **Ownership splitting.** §1 claims ownership granularity as a reason
   bundles exist — some bundles applied imperatively at bootstrap, the rest
   handed to a GitOps controller. That partition is not designed here. It
   interacts with `needs` in at least one awkward way: a bundle applied by
   one owner that `needs` a bundle applied by the other cannot be ordered by
   either owner alone.
2. **Charts that require hook ordering.** §3 says such a chart will not work
   unmodified. The migration path — split into bundles, or pre-render and
   patch — is not specified.
3. **Probe coverage.** `script` exists because some components expose no
   better signal. Whether the other seven probes cover everything else is an
   empirical question, answerable only by porting real floes.
4. **Where rendering happens.** This RFC assumes Helm is rendered at build
   time. Whether that stays true for charts that template against live
   cluster state is untested.

## 10. How to evaluate this concept alone

1. cert-manager's three readiness facts — CRDs established, webhook serving,
   issuer signing — are three bundles with three probes, and a consumer
   waits for the right ones via `backedBy`.
2. A floe's internal ordering is expressed entirely with `needs` and appears
   in no namespace another floe can read.
3. An ops command is written once, on the bundle holding the workload it
   targets, and interpolates that bundle's own namespace and workload name.
4. A handle names an object the declaring bundle renders, and a check
   catches it when it does not.
5. No wave index appears in any floe or bundle declaration.
6. A chart relying on Helm hook weights is rejected with an explanation, not
   silently mis-ordered.
