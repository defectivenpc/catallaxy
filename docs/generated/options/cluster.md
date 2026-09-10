# Cluster Options

Options for an individual cluster within a lab: Kubernetes settings, provisioners, phases, bundles, secrets projections, drift, lifecycle hooks, and authentication.

All options are under `lab.clusters.<name>.`

| Option | Type | Default |
| --- | --- | --- |
| [`assertions`](#assertions) | `list of (attribute set)` | `[ ]` |
| [`floes`](#floes) | `attribute set of raw value` | `{ }` |
| [`provides`](#provides) | `list of string` | `[ ]` |
| [`provisions`](#provisions) | `attribute set of (submodule)` | `{ }` |
| [`waitTimeout`](#waittimeout) | `string` | `"10m"` |
| [`warnings`](#warnings) | `list of string` | `[ ]` |
| [`colima.cpu`](#colima-cpu) | `positive integer, meaning >0` | `4` |
| [`colima.disk`](#colima-disk) | `positive integer, meaning >0` | `60` |
| [`colima.enable`](#colima-enable) | `boolean` | `pkgs.stdenv.isDarwin` |
| [`colima.memory`](#colima-memory) | `positive integer, meaning >0` | `8` |
| [`colima.profile`](#colima-profile) | `string` | `"catallaxy"` |
| [`edge.backend`](#edge-backend) | `null or string` |  |
| [`edge.httpPort`](#edge-httpport) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `what the provisioner answered` |
| [`edge.httpsPort`](#edge-httpsport) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `what the provisioner answered` |
| [`edge.mode`](#edge-mode) | `one of "proxy", "self", "none"` | `what the provisioner answered` |
| [`provisions.<name>.resourceKind`](#provisions-name-resourcekind) | `string` |  |
| [`provisions.<name>.resourceName`](#provisions-name-resourcename) | `string` | `the cluster's name` |
| [`secrets.project`](#secrets-project) | `attribute set of (submodule)` | `{ }` |
| [`secrets.project.<name>.keys`](#secrets-project-name-keys) | `attribute set of (submodule)` | `{ }` |
| [`secrets.project.<name>.keys.<name>.from`](#secrets-project-name-keys-name-from) | `string` |  |
| [`secrets.project.<name>.keys.<name>.jsonKey`](#secrets-project-name-keys-name-jsonkey) | `null or string` | `null` |
| [`secrets.project.<name>.keys.<name>.transform`](#secrets-project-name-keys-name-transform) | `one of "none", "base64", "json-wrap"` | `"none"` |
| [`secrets.project.<name>.namespace`](#secrets-project-name-namespace) | `string` | `"default"` |
| [`secrets.project.<name>.source`](#secrets-project-name-source) | `string` |  |
| [`secrets.publish`](#secrets-publish) | `attribute set of (submodule)` | `{ }` |
| [`secrets.publish.<name>.keys`](#secrets-publish-name-keys) | `list of string` | `[ ]` |
| [`secrets.publish.<name>.namespace`](#secrets-publish-name-namespace) | `string` |  |
| [`secrets.publish.<name>.secret`](#secrets-publish-name-secret) | `string` | `the attribute name` |
| [`secrets.publish.<name>.store`](#secrets-publish-name-store) | `null or string` | `null` |
| [`secrets.subscribe`](#secrets-subscribe) | `attribute set of (submodule)` | `{ }` |
| [`secrets.subscribe.<name>.annotations`](#secrets-subscribe-name-annotations) | `attribute set of string` | `{ }` |
| [`secrets.subscribe.<name>.fields`](#secrets-subscribe-name-fields) | `attribute set of string` | `{ }` |
| [`secrets.subscribe.<name>.from`](#secrets-subscribe-name-from) | `string` |  |
| [`secrets.subscribe.<name>.labels`](#secrets-subscribe-name-labels) | `attribute set of string` | `{ }` |
| [`secrets.subscribe.<name>.namespace`](#secrets-subscribe-name-namespace) | `string` |  |
| [`secrets.subscribe.<name>.refreshInterval`](#secrets-subscribe-name-refreshinterval) | `string` | `"1h"` |
| [`secrets.subscribe.<name>.secret`](#secrets-subscribe-name-secret) | `string` | `the attribute name` |
| [`secrets.subscribe.<name>.store`](#secrets-subscribe-name-store) | `null or string` | `null` |
| [`security.auditLogging.enable`](#security-auditlogging-enable) | `boolean` | `false` |
| [`security.auditLogging.level`](#security-auditlogging-level) | `one of "Metadata", "Request", "RequestResponse"` | `"Metadata"` |
| [`security.auditLogging.maxAgeDays`](#security-auditlogging-maxagedays) | `positive integer, meaning >0` | `7` |
| [`security.networkPolicies.defaultDeny`](#security-networkpolicies-defaultdeny) | `list of string` | `[ ]` |
| [`security.podSecurity.enable`](#security-podsecurity-enable) | `boolean` | `false` |
| [`security.podSecurity.enforce`](#security-podsecurity-enforce) | `one of "privileged", "baseline", "restricted"` | `"baseline"` |
| [`security.podSecurity.override`](#security-podsecurity-override) | `attribute set of (one of "privileged", "baseline", "restricted")` | `{ }` |
| [`security.podSecurity.warn`](#security-podsecurity-warn) | `one of "privileged", "baseline", "restricted"` | `"restricted"` |

## Top level

### `assertions` {#assertions}

Config-validity checks scoped to this cluster, including every one
its floes declared. `lib/lab.nix` reads these and throws, so a
violated assertion fails `nix eval` rather than reaching a cluster.

**Type:** `list of (attribute set)`

**Default:** `[ ]`

**Declared in:** modules/lab/types.nix

---
### `floes` {#floes}

Instantiated floes, keyed by the name they link under. One of them
must provide `KUBERNETES_CLUSTER`; the rest are what installs into
it.

Values are `.instantiate { ... }` results, not modules — a floe is
an instance, and the linker resolves between instances.

**Type:** `attribute set of raw value`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `provides` {#provides}

Promises this cluster offers to the lab, as `<unit>/<provide>`.

A link is per-cluster, so `requires.mesh = MESH_NETWORK` finds only
what is in the same cluster — right for almost everything, and wrong
for the few things a lab has one of. Naming a promise here puts it
in the lab's scope, where every *other* cluster resolves it if
nothing of its own answers first.

Nearer wins, so offering something lab-wide cannot break a cluster
that already has its own: a cluster with a gateway keeps it, and one
without picks up the lab's.

Per promise rather than per unit, because one floe holds both kinds.
`netbird` provides `MESH_NETWORK`, which is the whole point of a
mesh, and `MESH_ADMIN`, which is a reference to a Secret in this
cluster and can never mean anything anywhere else — offering the
unit would offer both, and `link` is right to refuse the second.

Opt-in rather than automatic, for the same reason: a cluster's floes
promise plenty that is meaningless elsewhere. What is *readable*
across the boundary is then decided per field by `T.local`; see
`lib/floe-core/link.nix`.

**Type:** `list of string`

**Default:** `[ ]`

**Example:**
```nix
[
  "netbird/mesh"
]
```

**Declared in:** modules/lab/types.nix

---
### `provisions` {#provisions}

Keyed as the clusters are named under `lab.clusters`.

A cluster named here must exist in the lab and must be provisioned
externally — one this machine creates is not something a controller
elsewhere also creates, and both trying is the failure that produces
two clusters and one name.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `waitTimeout` {#waittimeout}

How long a bundle may take to reconcile before the apply gives up.

**Type:** `string`

**Default:** `"10m"`

**Declared in:** modules/lab/types.nix

---
### `warnings` {#warnings}

Soft advisories from this cluster's floes, already prefixed with the
floe that raised them. Carried into `metadata.json` rather than
failing evaluation.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/types.nix

---
## `colima`

### `colima.cpu` {#colima-cpu}

vCPUs for the VM.

**Type:** `positive integer, meaning >0`

**Default:** `4`

**Declared in:** modules/lab/types.nix

---
### `colima.disk` {#colima-disk}

GiB of disk for the VM.

**Type:** `positive integer, meaning >0`

**Default:** `60`

**Declared in:** modules/lab/types.nix

---
### `colima.enable` {#colima-enable}

Run docker through a colima VM. A host fact rather than a cluster
one, which is why it lives on the lab and not in the cluster floe.

**Type:** `boolean`

**Default:** `pkgs.stdenv.isDarwin`

**Declared in:** modules/lab/types.nix

---
### `colima.memory` {#colima-memory}

GiB of RAM for the VM.

**Type:** `positive integer, meaning >0`

**Default:** `8`

**Declared in:** modules/lab/types.nix

---
### `colima.profile` {#colima-profile}

Colima profile name.

**Type:** `string`

**Default:** `"catallaxy"`

**Declared in:** modules/lab/types.nix

---
## `edge`

### `edge.backend` {#edge-backend}

Hostname the lab's proxy connects to for this cluster, resolved
on the lab's docker network.

Null unless `mode` is `proxy`. A cluster the lab fronts and
cannot name a backend for is refused, rather than rendering a
route to a name that resolves to nothing and timing out every
request through it.

**Type:** `null or string`

**Default:** `the backend the provisioner named, when the lab is this cluster's edge`

**Declared in:** modules/lab/types.nix

---
### `edge.httpPort` {#edge-httpport}

Port the proxy dials for plain HTTP, at the backend.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `what the provisioner answered`

**Declared in:** modules/lab/types.nix

---
### `edge.httpsPort` {#edge-httpsport}

Port the proxy dials for HTTPS, at the backend.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `what the provisioner answered`

**Declared in:** modules/lab/types.nix

---
### `edge.mode` {#edge-mode}

Who fronts this cluster.

`proxy` — the lab does, at `backend`. `self` — the cluster is
its own edge and the lab routes nothing to it, which is what a
managed cluster in a cloud answers. `none` — nothing routes to
it at all.

`self` is a refusal to route rather than a deferred address:
the lab has nothing to say about how to reach the cluster, and
saying nothing is a complete answer.

**Type:** `one of "proxy", "self", "none"`

**Default:** `what the provisioner answered`

**Declared in:** modules/lab/types.nix

---
## `provisions`

### `provisions.<name>.resourceKind` {#provisions-name-resourcekind}

Fully qualified CR kind that represents the cluster.

**Type:** `string`

**Example:** `"clusters.kubernetes.digitalocean.crossplane.io"`

**Declared in:** modules/lab/types.nix

---
### `provisions.<name>.resourceName` {#provisions-name-resourcename}

Name of that CR. Defaults to the lab's name for the
cluster, which is what a floe rendering the CR from this
declaration would use anyway.

**Type:** `string`

**Default:** `the cluster's name`

**Declared in:** modules/lab/types.nix

---
## `secrets`

### `secrets.project` {#secrets-project}

Secrets projected into this cluster from the lab's stores.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.keys` {#secrets-project-name-keys}

Which keys to project, and under what names.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.keys.<name>.from` {#secrets-project-name-keys-name-from}

Key in the managed secret this one is taken from.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.keys.<name>.jsonKey` {#secrets-project-name-keys-name-jsonkey}

Key name inside the object, for `json-wrap`.

**Type:** `null or string`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.keys.<name>.transform` {#secrets-project-name-keys-name-transform}

How the value is encoded on the way in.

**Type:** `one of "none", "base64", "json-wrap"`

**Default:** `"none"`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.namespace` {#secrets-project-name-namespace}

Namespace the Secret lands in.

**Type:** `string`

**Default:** `"default"`

**Declared in:** modules/lab/types.nix

---
### `secrets.project.<name>.source` {#secrets-project-name-source}

Which `lab.secrets.managed` entry supplies the values.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `secrets.publish` {#secrets-publish}

Runtime values this cluster shares with the rest of the lab.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.publish.<name>.keys` {#secrets-publish-name-keys}

Which keys to push. Empty publishes the Secret whole,
which is what you want for a credential minted as one
thing.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/types.nix

---
### `secrets.publish.<name>.namespace` {#secrets-publish-name-namespace}

Namespace holding the Secret to publish.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `secrets.publish.<name>.secret` {#secrets-publish-name-secret}

The local Secret whose value is pushed.

**Type:** `string`

**Default:** `the attribute name`

**Declared in:** modules/lab/types.nix

---
### `secrets.publish.<name>.store` {#secrets-publish-name-store}

Which `lab.secrets.stores` entry to push into.

**Type:** `null or string`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe` {#secrets-subscribe}

Runtime values this cluster reads from another cluster in the lab.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.annotations` {#secrets-subscribe-name-annotations}

Annotations on the materialised Secret.

**Type:** `attribute set of string`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.fields` {#secrets-subscribe-name-fields}

Rewrite the published keys on the way in.

A credential arrives as whatever the minting cluster
called it, and the consumer usually wants it under a
different name beside some constants: a token becomes
`password`, next to the `url` and `username` that identify
what it opens. `{{ .<key> }}` reads a published key;
anything else is literal. Empty materialises the published
keys unchanged.

**Type:** `attribute set of string`

**Default:** `{ }`

**Example:**
```nix
{
  password = "{{ .token }}";
  username = "admin";
}
```

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.from` {#secrets-subscribe-name-from}

The cluster in this lab that publishes it.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.labels` {#secrets-subscribe-name-labels}

Labels on the materialised Secret.

What reads a Secret often finds it by label rather than by
name — argocd treats one labelled
`argocd.argoproj.io/secret-type: repository` as a
repository registration. Without this a subscriber can
receive the value and have nothing notice it arrived.

**Type:** `attribute set of string`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.namespace` {#secrets-subscribe-name-namespace}

Namespace the Secret should land in here.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.refreshInterval` {#secrets-subscribe-name-refreshinterval}

How often to re-read the store.

**Type:** `string`

**Default:** `"1h"`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.secret` {#secrets-subscribe-name-secret}

What to call the Secret locally.

**Type:** `string`

**Default:** `the attribute name`

**Declared in:** modules/lab/types.nix

---
### `secrets.subscribe.<name>.store` {#secrets-subscribe-name-store}

Which `lab.secrets.stores` entry to read from.

**Type:** `null or string`

**Declared in:** modules/lab/types.nix

---
## `security`

### `security.auditLogging.enable` {#security-auditlogging-enable}

Record what the API server was asked to do.

Off by default: it is the one control here that costs something
at runtime, and on a laptop lab the log is usually read never.
Turned on, it is the only way to answer what changed a resource
after the fact.

k3d only. A managed control plane logs through its provider, and
a cluster this lab did not make has no server to pass flags to.

**Type:** `boolean`

**Default:** `false`

**Declared in:** modules/lab/types.nix

---
### `security.auditLogging.level` {#security-auditlogging-level}

How much of each request is recorded.

`Metadata` is who, what and when. `Request` adds the submitted
object and `RequestResponse` the returned one — both of which
write Secret contents to the log, which is why neither is the
default.

**Type:** `one of "Metadata", "Request", "RequestResponse"`

**Default:** `"Metadata"`

**Declared in:** modules/lab/types.nix

---
### `security.auditLogging.maxAgeDays` {#security-auditlogging-maxagedays}

How long a rotated audit log is kept.

**Type:** `positive integer, meaning >0`

**Default:** `7`

**Declared in:** modules/lab/types.nix

---
### `security.networkPolicies.defaultDeny` {#security-networkpolicies-defaultdeny}

Namespaces that deny all traffic except what a policy allows.
DNS to kube-system is excepted, because a namespace whose pods
cannot resolve turns every failure into a name error.

A list rather than a flag, and not the whole cluster: a
NetworkPolicy is additive, so denying a namespace means every
floe installing into it must declare the traffic it needs. No
floe declares any today. Naming one namespace at a time is what
makes that a decision per namespace instead of an outage.

Refused on a cluster whose CNI does not enforce policy — see the
assertion below.

**Type:** `list of string`

**Default:** `[ ]`

**Example:**
```nix
[
  "podinfo"
]
```

**Declared in:** modules/lab/types.nix

---
### `security.podSecurity.enable` {#security-podsecurity-enable}

Label every namespace this cluster creates for Pod Security
Admission.

Off by default because turning it on can refuse a workload that
was running, and that refusal should be somebody's decision. It
costs nothing to run: PSA is in the API server, so unlike a
NetworkPolicy it needs no CNI support and is enforced identically
on k3d and on a cloud cluster.

**Type:** `boolean`

**Default:** `false`

**Declared in:** modules/lab/types.nix

---
### `security.podSecurity.enforce` {#security-podsecurity-enforce}

The level the API server refuses pods below.

`baseline` blocks the known privilege escalations and admits most
upstream charts unchanged. `restricted` additionally requires
non-root, a seccomp profile and dropped capabilities, which many
charts need values changes to satisfy.

**Type:** `one of "privileged", "baseline", "restricted"`

**Default:** `"baseline"`

**Declared in:** modules/lab/types.nix

---
### `security.podSecurity.override` {#security-podsecurity-override}

Namespaces that enforce a level other than `enforce`, keyed by
namespace. It reads in both directions.

Down, because a CNI or a storage driver genuinely needs host
access, and the alternative is turning the whole cluster down to
the level its most privileged component needs. Up, because a
workload that already satisfies `restricted` should be held to
it rather than to the cluster default.

**Type:** `attribute set of (one of "privileged", "baseline", "restricted")`

**Default:** `{ }`

**Example:**
```nix
{
  cilium = "privileged";
  podinfo = "restricted";
}
```

**Declared in:** modules/lab/types.nix

---
### `security.podSecurity.warn` {#security-podsecurity-warn}

The level a violation is warned about at, without being refused.

Defaulted stricter than `enforce` on purpose: the warnings are
what tells you whether raising `enforce` would break anything,
and they cost nothing until you read them.

**Type:** `one of "privileged", "baseline", "restricted"`

**Default:** `"restricted"`

**Declared in:** modules/lab/types.nix

---
