# Lab Options

Lab-scope options: identity, CD strategy, DNS, networking, secrets, images, lint, plan steps, and operations.

| Option | Type | Default |
| --- | --- | --- |
| [`assertions`](#assertions) | `list of (submodule)` | `[ ]` |
| [`clusters`](#clusters) | `attribute set of (submodule)` | `{ }` |
| [`name`](#name) | `string` |  |
| [`provides`](#provides) | `attribute set of raw value` | `{ }` |
| [`steps`](#steps) | `attribute set of (submodule)` | `{ }` |
| [`unstable`](#unstable) | `null or string` | `null` |
| [`warnings`](#warnings) | `list of string` | `[ ]` |
| [`assertions.*.assertion`](#assertions-assertion) | `boolean` |  |
| [`assertions.*.message`](#assertions-message) | `string` |  |
| [`dns.configureHost`](#dns-configurehost) | `boolean` | `false` |
| [`dns.containerName`](#dns-containername) | `string` | `"catallaxy-${config.lab.name}-dns"` |
| [`dns.enable`](#dns-enable) | `boolean` | `false` |
| [`dns.hostPort`](#dns-hostport) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `5354` |
| [`dns.image`](#dns-image) | `string` | `"cznic/knot:latest"` |
| [`dns.out.dnsInfo`](#dns-out-dnsinfo) | `null or (attribute set)` | `null` |
| [`dns.out.service`](#dns-out-service) | `attribute set` | `{ }` |
| [`dns.port`](#dns-port) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `config.lab.dns.hostPort` |
| [`dns.server`](#dns-server) | `string` | `config.lab.network.gateway` |
| [`dns.tsigKeyname`](#dns-tsigkeyname) | `string` | `"externaldns-key"` |
| [`dns.tsigSecret`](#dns-tsigsecret) | `string` |  |
| [`dns.tsigSecretAlg`](#dns-tsigsecretalg) | `string` | `"hmac-sha256"` |
| [`dns.zone`](#dns-zone) | `string` | `"${config.lab.name}.test"` |
| [`egress.containerName`](#egress-containername) | `string` | `"catallaxy-${config.lab.name}-egress"` |
| [`egress.enable`](#egress-enable) | `boolean` | `config.lab.proxy.enable` |
| [`egress.image`](#egress-image) | `string` |  |
| [`egress.out.service`](#egress-out-service) | `attribute set` | `{ }` |
| [`egress.port`](#egress-port) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `3128` |
| [`network.gateway`](#network-gateway) | `string` | `the address after the subnet's own` |
| [`network.subnet`](#network-subnet) | `string` | `"172.20.0.0/16"` |
| [`out.cloudE2e.eligible`](#out-cloude2e-eligible) | `boolean` |  |
| [`out.cloudE2e.providers`](#out-cloude2e-providers) | `list of string` | `[ ]` |
| [`out.cloudE2e.reasons`](#out-cloude2e-reasons) | `list of string` | `[ ]` |
| [`out.cloudE2e.requiredEnv`](#out-cloude2e-requiredenv) | `list of string` | `[ ]` |
| [`out.cloudE2e.tag`](#out-cloude2e-tag) | `string` |  |
| [`out.selfContained.eligible`](#out-selfcontained-eligible) | `boolean` |  |
| [`out.selfContained.envFile`](#out-selfcontained-envfile) | `null or string` | `null` |
| [`out.selfContained.reasons`](#out-selfcontained-reasons) | `list of string` | `[ ]` |
| [`out.selfContained.unstable`](#out-selfcontained-unstable) | `null or string` | `null` |
| [`proxy.containerName`](#proxy-containername) | `string` | `"catallaxy-${config.lab.name}-ingress"` |
| [`proxy.enable`](#proxy-enable) | `boolean` | `false` |
| [`proxy.httpPort`](#proxy-httpport) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `80` |
| [`proxy.httpsPort`](#proxy-httpsport) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `443` |
| [`proxy.idleTimeout`](#proxy-idletimeout) | `string` | `"1h"` |
| [`proxy.image`](#proxy-image) | `string` | `"haproxy:3.1-alpine"` |
| [`proxy.out.hosts`](#proxy-out-hosts) | `list of string` | `[ ]` |
| [`proxy.out.service`](#proxy-out-service) | `attribute set` | `{ }` |
| [`proxy.tls.enable`](#proxy-tls-enable) | `boolean` | `true` |
| [`registry.containerName`](#registry-containername) | `string` | `"catallaxy-${config.lab.name}-registry"` |
| [`registry.enable`](#registry-enable) | `boolean` | `false` |
| [`registry.image`](#registry-image) | `string` |  |
| [`registry.port`](#registry-port) | `16 bit unsigned integer; between 0 and 65535 (both inclusive)` | `5050` |
| [`registry.service`](#registry-service) | `attribute set` | `{ }` |
| [`registry.upstreams`](#registry-upstreams) | `list of (submodule)` |  |
| [`registry.upstreams.*.host`](#registry-upstreams-host) | `string` |  |
| [`registry.upstreams.*.prefixes`](#registry-upstreams-prefixes) | `list of string` | `[ ]` |
| [`registry.upstreams.*.tlsVerify`](#registry-upstreams-tlsverify) | `boolean` | `true` |
| [`registry.upstreams.*.url`](#registry-upstreams-url) | `string` |  |
| [`registry.warmCache`](#registry-warmcache) | `boolean` | `true` |
| [`secrets.envFile`](#secrets-envfile) | `null or string` | `null` |
| [`secrets.managed`](#secrets-managed) | `attribute set of (submodule)` | `{ }` |
| [`secrets.managed.<name>.hostPaths`](#secrets-managed-name-hostpaths) | `attribute set of string` | `{ }` |
| [`secrets.managed.<name>.keys`](#secrets-managed-name-keys) | `attribute set of (submodule)` | `{ }` |
| [`secrets.managed.<name>.keys.<name>.generator`](#secrets-managed-name-keys-name-generator) | `null or one of "base64", "hex", "alphanumeric", "uuid"` | `null` |
| [`secrets.managed.<name>.keys.<name>.length`](#secrets-managed-name-keys-name-length) | `null or (positive integer, meaning >0)` | `null` |
| [`secrets.managed.<name>.kind`](#secrets-managed-name-kind) | `one of "value", "ca"` | `"value"` |
| [`secrets.managed.<name>.store`](#secrets-managed-name-store) | `string` |  |
| [`secrets.stores`](#secrets-stores) | `attribute set of (submodule)` | `{ }` |
| [`secrets.stores.<name>.backend`](#secrets-stores-name-backend) | `one of "sops", "env", "vault", "external"` | `"sops"` |
| [`secrets.stores.<name>.direction`](#secrets-stores-name-direction) | `one of "authored", "runtime"` |  |
| [`secrets.stores.<name>.remover.command`](#secrets-stores-name-remover-command) | `null or (list of string)` | `null` |
| [`secrets.stores.<name>.vault.path`](#secrets-stores-name-vault-path) | `string` | `"secret"` |
| [`secrets.stores.<name>.vault.server`](#secrets-stores-name-vault-server) | `null or string` | `null` |
| [`secrets.stores.<name>.vault.version`](#secrets-stores-name-vault-version) | `one of "v1", "v2"` | `"v2"` |
| [`secrets.stores.<name>.writer.command`](#secrets-stores-name-writer-command) | `null or (list of string)` | `null` |
| [`verify.endpoints.acceptStatuses`](#verify-endpoints-acceptstatuses) | `list of integer between 100 and 599 (both inclusive)` | `[ ]` |
| [`verify.endpoints.enable`](#verify-endpoints-enable) | `boolean` | `true` |

## Top level

### `assertions` {#assertions}

Hard config-validity checks at lab scope. A failed entry fails
evaluation, so it blocks every command that evaluates the lab.

**Type:** `list of (submodule)`

**Default:** `[ ]`

**Declared in:** modules/lab/types.nix

---
### `clusters` {#clusters}

The clusters this lab builds. Each one links its floes and elaborates
them into a cluster picture; the lab lowers that into what the CLI
reads.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/types.nix

---
### `name` {#name}

Unique name for the lab. Also the docker network name and the prefix
on every k3d container, so two labs on one host do not collide.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
### `provides` {#provides}

Floes linked at lab scope, whose provides every cluster can resolve.

The other direction from `lab.clusters.<c>.provides`: that offers a
cluster's promise upward, this declares one the lab makes itself. A
floe here installs nothing — there is no cluster for it to render
into — and exists to answer a signature, which is how a fact the lab
holds reaches the floes that need it without being threaded through
every instantiation by hand.

These are linked on their own, with no scope of their own, so **the
lab's provides cannot depend on any cluster**. That is RFC 0005 §6.2's
stratification, enforced by construction rather than by a rule nobody
checks: a container's provisions come from its own configuration, its
contents read them, and the aggregate folds the contents.

**Type:** `attribute set of raw value`

**Default:** `{ }`

**Example:** `{ zone = floes.lab-zone { ... }; }`

**Declared in:** modules/lab/types.nix

---
### `steps` {#steps}

Steps the lab itself contributes, beside the ones the framework emits
and the ones its floes declare.

For work that is neither applying a manifest nor provisioning: checking
a precondition, running a script, waiting on something outside the
cluster.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/planner

---
### `unstable` {#unstable}

Why this lab is not expected to stand up, or null when it is.

Not every lab can be made to stand up as fast as it can be made to
render, and a lab that renders but does not deploy is worth
having in the tree: it renders, it lints, its plan is snapshotted, and
its digest is pinned, so the ninety-odd checks that do not need a
cluster all apply to it. What it must not do is fail in CI as though
someone had broken it.

A string rather than a bool, because "unstable" with no reason is a
note to nobody. It joins `lab.out.selfContained.reasons`, so the e2e
runner skips the lab and prints this, and `nix/checks/self-contained.nix`
pins it — a lab going unstable, becoming stable, or quietly staying
unstable forever is a diff in that table either way.

This is the one declared entry among derived ones. Everything else in
`selfContained` is read off the lab; this cannot be, because "the
operator races on a fresh install" is not a fact any expression here
can compute.

**Type:** `null or string`

**Example:** `"netbird's setup key has to be fetched by hand; see floes/cluster/netbird."`

**Declared in:** modules/lab/types.nix

---
### `warnings` {#warnings}

Soft advisories at lab scope, carried into `metadata.json` and
surfaced by `cata lab lint`.

The counterpart to `assertions`: something worth saying that is not
worth refusing to build over. A floe's warnings arrive here already
prefixed with the floe that raised them.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/types.nix

---
## `assertions`

### `assertions.*.assertion` {#assertions-assertion}

True = check passes. False = violation reported.

**Type:** `boolean`

**Declared in:** modules/lab/types.nix

---
### `assertions.*.message` {#assertions-message}

Diagnostic shown when the assertion fails. Name the option path and
what the user should change.

**Type:** `string`

**Declared in:** modules/lab/types.nix

---
## `dns`

### `dns.configureHost` {#dns-configurehost}

Point this machine's resolver at the lab's DNS during `cata lab up`,
so `*.<zone>` resolves in a browser and in anything run by hand.

Off by default because it needs `sudo` and edits configuration outside
the lab, which is a poor default for a command whose job is to be
reversible. Left off, `cata lab verify` still probes every exposed
host by resolving through the lab's own DNS, and
`curl --resolve <host>:80:127.0.0.1` does the same by hand.

`cata lab destroy` removes what it wrote.

**Type:** `boolean`

**Default:** `false`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.containerName` {#dns-containername}

Docker container name for the DNS server.

**Type:** `string`

**Default:** `"catallaxy-${config.lab.name}-dns"`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.enable` {#dns-enable}

Whether to enable an authoritative DNS server for the lab's zone.

**Type:** `boolean`

**Default:** `false`

**Example:** `true`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.hostPort` {#dns-hostport}

Host-mapped port for the DNS server.

5354 avoids 5353, which is mDNS. A lab moving off the default so it
can run beside another should also skip 5355: that is LLMNR, which
systemd-resolved holds on most Linux hosts, so it looks free in a
table of registered names and is not.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `5354`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.image` {#dns-image}

Knot DNS container image.

**Type:** `string`

**Default:** `"cznic/knot:latest"`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.out.dnsInfo` {#dns-out-dnsinfo}

What `cata lab dns` needs to point the host resolver here. Null when
the lab runs no DNS, which is how the CLI knows to say so rather
than to configure a resolver pointing at nothing.

**Type:** `null or (attribute set)`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.out.service` {#dns-out-service}

The `HostService` record `setup-services` starts.

**Type:** `attribute set`

**Default:** `{ }`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.port` {#dns-port}

Port clusters reach the DNS server on.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `config.lab.dns.hostPort`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.server` {#dns-server}

Where the DNS server answers from, as seen from inside the lab
network. The bridge gateway, because that address is reachable both
from pods and from the host.

**Type:** `string`

**Default:** `config.lab.network.gateway`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.tsigKeyname` {#dns-tsigkeyname}

TSIG key name for RFC2136 dynamic updates.

**Type:** `string`

**Default:** `"externaldns-key"`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.tsigSecret` {#dns-tsigsecret}

Base64 TSIG secret.

A fixed default, and deliberately so: this authorises updates to a
throwaway zone served on loopback, and generating one per lab would
put a value in the store that every lab then has to be told. A lab
that exposes its DNS beyond the host should set its own.

**Type:** `string`

**Default:** `"kp4bgnFAVCmajGIqOW7rj0MNwRNZHBqMvYaLTwzPHgI="`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.tsigSecretAlg` {#dns-tsigsecretalg}

TSIG algorithm.

**Type:** `string`

**Default:** `"hmac-sha256"`

**Declared in:** modules/lab/network/dns.nix

---
### `dns.zone` {#dns-zone}

Domain the lab's hostnames hang off, handed to floes as their
`baseDomain`.

Meaningful even with `enable = false`: it is what routes are declared
under and what `registry-setup` names the in-cluster registry at. What
`enable` adds is something that answers for it.

**Type:** `string`

**Default:** `"${config.lab.name}.test"`

**Declared in:** modules/lab/network/dns.nix

---
## `egress`

### `egress.containerName` {#egress-containername}

Docker container name for the forward proxy.

**Type:** `string`

**Default:** `"catallaxy-${config.lab.name}-egress"`

**Declared in:** modules/lab/host/egress.nix

---
### `egress.enable` {#egress-enable}

Whether to enable a forward proxy inside the lab network, so host tools can reach lab hostnames.

**Type:** `boolean`

**Default:** `config.lab.proxy.enable`

**Example:** `true`

**Declared in:** modules/lab/host/egress.nix

---
### `egress.image` {#egress-image}

tinyproxy container image.

**Type:** `string`

**Default:** `"ghcr.io/querateam/docker-tinyproxy:latest"`

**Declared in:** modules/lab/host/egress.nix

---
### `egress.out.service` {#egress-out-service}

The `HostService` record `setup-services` starts.

**Type:** `attribute set`

**Default:** `{ }`

**Declared in:** modules/lab/host/egress.nix

---
### `egress.port` {#egress-port}

Loopback port the forward proxy is published on.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `3128`

**Declared in:** modules/lab/host/egress.nix

---
## `network`

### `network.gateway` {#network-gateway}

Gateway address within the subnet.

**Type:** `string`

**Default:** `the address after the subnet's own`

**Declared in:** modules/lab/types.nix

---
### `network.subnet` {#network-subnet}

Docker network the lab's containers share, in CIDR form. `cata lab up`
parses this before it runs anything, to refuse a lab whose subnet
overlaps one already on the host.

**Type:** `string`

**Default:** `"172.20.0.0/16"`

**Declared in:** modules/lab/types.nix

---
## `out`

### `out.cloudE2e.eligible` {#out-cloude2e-eligible}

True when this lab can be stood up against a real account unattended.

**Type:** `boolean`

**Declared in:** modules/lab/e2e-cloud.nix

---
### `out.cloudE2e.providers` {#out-cloude2e-providers}

Cloud providers this lab's stacks name. Empty for a lab that reaches nothing.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/e2e-cloud.nix

---
### `out.cloudE2e.reasons` {#out-cloude2e-reasons}

What stands in the way, one sentence each. Empty exactly when `eligible`.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/e2e-cloud.nix

---
### `out.cloudE2e.requiredEnv` {#out-cloude2e-requiredenv}

Variables the runner refuses to start without.

Checked before anything is created rather than discovered by an
apply: a missing token halfway through leaves whatever the first
half made, and nothing that knows to clean it up.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/e2e-cloud.nix

---
### `out.cloudE2e.tag` {#out-cloude2e-tag}

The tag every object this lab creates carries.

What makes a leak findable. A cluster nobody can list by lab is a
cluster nobody notices is still running, and the reaper has
nothing to go on.

**Type:** `string`

**Declared in:** modules/lab/e2e-cloud.nix

---
### `out.selfContained.eligible` {#out-selfcontained-eligible}

True when nothing stands between this lab and a machine with docker on it.

**Type:** `boolean`

**Declared in:** modules/lab/e2e.nix

---
### `out.selfContained.envFile` {#out-selfcontained-envfile}

File the runner loads before the lab starts, relative to the flake
root. Null when the lab needs nothing from the environment.

**Type:** `null or string`

**Declared in:** modules/lab/e2e.nix

---
### `out.selfContained.reasons` {#out-selfcontained-reasons}

What does stand in the way, one sentence each. Empty exactly when `eligible`.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/e2e.nix

---
### `out.selfContained.unstable` {#out-selfcontained-unstable}

`lab.unstable`, carried through so a reader can tell the two kinds
of ineligible apart.

A lab held out because its secrets live in sops is a lab that
works and is not runnable *here*. A lab held out because it is
mid-migration is a lab nobody claims works at all. Both are
ineligible and only one is a thing to finish.

**Type:** `null or string`

**Declared in:** modules/lab/e2e.nix

---
## `proxy`

### `proxy.containerName` {#proxy-containername}

Docker container name for the ingress.

**Type:** `string`

**Default:** `"catallaxy-${config.lab.name}-ingress"`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.enable` {#proxy-enable}

Whether to enable an HAProxy ingress in front of the clusters' gateways.

**Type:** `boolean`

**Default:** `false`

**Example:** `true`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.httpPort` {#proxy-httpport}

Loopback port the HTTP listener is published on.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `80`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.httpsPort` {#proxy-httpsport}

Loopback port the HTTPS listener is published on.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `443`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.idleTimeout` {#proxy-idletimeout}

How long an idle connection is held open.

Long, deliberately. HAProxy's defaults are tens of seconds, which
orderly-closes the long-lived streams that gRPC and watch-based
clients keep open — and the symptom is not a failure but a client
that silently reconnects forever.

**Type:** `string`

**Default:** `"1h"`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.image` {#proxy-image}

HAProxy container image.

**Type:** `string`

**Default:** `"haproxy:3.1-alpine"`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.out.hosts` {#proxy-out-hosts}

Every hostname this ingress answers for.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.out.service` {#proxy-out-service}

The `HostService` record `setup-services` starts.

**Type:** `attribute set`

**Default:** `{ }`

**Declared in:** modules/lab/host/proxy.nix

---
### `proxy.tls.enable` {#proxy-tls-enable}

Terminate TLS with the lab's own CA, and redirect plain HTTP to it.

The certificate is minted by the `cert-generate` step, which is
emitted only when this is on. It is also what puts a CA on disk for
the cluster's issuer to sign from, so turning this off leaves the
lab with no root at all.

**Type:** `boolean`

**Default:** `true`

**Declared in:** modules/lab/host/proxy.nix

---
## `registry`

### `registry.containerName` {#registry-containername}

Docker container name, which is also how a running lab's registry is identified.

**Type:** `string`

**Default:** `"catallaxy-${config.lab.name}-registry"`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.enable` {#registry-enable}

Whether to enable a Zot pull-through cache in front of the registries this lab pulls from.

**Type:** `boolean`

**Default:** `false`

**Example:** `true`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.image` {#registry-image}

Zot container image.

**Type:** `string`

**Default:** `"ghcr.io/project-zot/zot-linux-amd64:v2.1.17"`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.port` {#registry-port}

Host port the registry listens on.

**Type:** `16 bit unsigned integer; between 0 and 65535 (both inclusive)`

**Default:** `5050`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.service` {#registry-service}

The `HostService` record `setup-services` starts.

**Type:** `attribute set`

**Default:** `{ }`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.upstreams` {#registry-upstreams}

The registries the cache sits in front of. Each entry becomes both a
zot sync source and a `mirrors:` entry in the `registries.yaml` every
node mounts.

Add one when a floe pulls from an upstream not listed here. Missing
the entry, containerd goes to the public registry directly and has to
resolve its name itself — which a lab node cannot do once the lab
runs its own DNS: that server is authoritative for the zone and
answers REFUSED for everything else, which a resolver treats as an
answer rather than a reason to ask elsewhere. The pull then fails on
a name that resolves perfectly well from the host.

**Type:** `list of (submodule)`

**Default:**
```nix
[
  {
    host = "codeberg.org";
    prefixes = [
      "forgejo/**"
    ];
    url = "https://codeberg.org";
  }
  {
    host = "registry.k8s.io";
    url = "https://registry.k8s.io";
  }
  {
    host = "ghcr.io";
    url = "https://ghcr.io";
  }
  {
    host = "quay.io";
    url = "https://quay.io";
  }
  {
    host = "docker.io";
    url = "https://registry-1.docker.io";
  }
  {
    host = "public.ecr.aws";
    url = "https://public.ecr.aws";
  }
  {
    host = "xpkg.upbound.io";
    url = "https://xpkg.upbound.io";
  }
  {
    host = "oci.external-secrets.io";
    url = "https://oci.external-secrets.io";
  }
]
```

**Declared in:** modules/lab/host/registry.nix

---
### `registry.upstreams.*.host` {#registry-upstreams-host}

Bare upstream registry hostname, no scheme. This is the name
containerd looks a mirror up under, so it must match the prefix in
image references exactly — `docker.io/foo/bar`,
`codeberg.org/forgejo/forgejo`.

**Type:** `string`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.upstreams.*.prefixes` {#registry-upstreams-prefixes}

Repository prefixes this upstream is responsible for. When set,
zot's sync only consults it for repos matching one of them.

Purely a latency concern, and a large one: without prefixes zot
walks every configured upstream in declared order on each cold
pull, ignoring containerd's `?ns=<host>` hint. Naming the prefixes
of a single-tenant registry removes the dead-end iteration that
dominates cold-pull time.

**Type:** `list of string`

**Default:** `[ ]`

**Example:**
```nix
[
  "forgejo/**"
]
```

**Declared in:** modules/lab/host/registry.nix

---
### `registry.upstreams.*.tlsVerify` {#registry-upstreams-tlsverify}

Whether zot validates the upstream's TLS certificate.

**Type:** `boolean`

**Default:** `true`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.upstreams.*.url` {#registry-upstreams-url}

The URL zot syncs from: scheme, host, and any path. For most
registries this is just `https://<host>`; the oddity is Docker Hub,
whose `docker.io` name resolves to `https://registry-1.docker.io`.

Separate from `host` because the two are genuinely different
strings for the same registry, and each side needs its own.

**Type:** `string`

**Declared in:** modules/lab/host/registry.nix

---
### `registry.warmCache` {#registry-warmcache}

Pull every image the lab's manifests reference into the cache before
any cluster is created.

Without it the first apply triggers zot's on-demand sync while the
kubelet's image-pull deadline and the applier's rollout timeout are
already running, and a slow upstream shows up as a rollout failure
rather than as a slow pull.

The step reads `images.txt` from the lab package and asks zot for
each entry, which is what makes zot fetch it. Set this false when
iterating on an apply and the up-front warm is not worth the wait.

**Type:** `boolean`

**Default:** `true`

**Declared in:** modules/lab/host/registry.nix

---
## `secrets`

### `secrets.envFile` {#secrets-envfile}

A file a runner sources before the lab starts, for `env`-backed
stores.

A repository-relative path rather than a Nix path: a Nix path resolves
into the store, which under lazy trees names something never written
to disk, so the runner is handed a path that does not exist. The
relative form is also what a human can act on — it is the argument to
`git add`.

Catallaxy never reads it. The environment is the interface; this only
names one way to fill it.

**Type:** `null or string`

**Example:** `"examples/labs/gitops/envs/ci.env"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed` {#secrets-managed}

Secrets catallaxy mints or holds for you. A value a floe could
generate for itself does not belong here — see `mkGeneratedSecret`.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.hostPaths` {#secrets-managed-name-hostpaths}

Keys to write to the host during `cata lab up`'s preflight, before
any service starts. `$LAB_STATE_DIR` expands to the lab's state
directory.

A key named `*.crt` is written 0644 and everything else 0600 — the
CLI decides on the suffix, not on `kind`, so a file that must be
world-readable has to be named for it.

**Type:** `attribute set of string`

**Default:** `{ }`

**Example:**
```nix
{
  "ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
}
```

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.keys` {#secrets-managed-name-keys}

The keys this secret holds.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.keys.<name>.generator` {#secrets-managed-name-keys-name-generator}

How `cata secrets generate` mints this key. Null means you set it by
hand with `cata secrets edit`.

An enum, though the CLI takes any string: an unknown generator is
only rejected when someone runs the mint, and by then the store file
exists and the failure looks like a tooling problem.

**Type:** `null or one of "base64", "hex", "alphanumeric", "uuid"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.keys.<name>.length` {#secrets-managed-name-keys-name-length}

Entropy in bytes for `base64`, characters otherwise. Required by
every generator but `uuid`, and capped at 4096 by the CLI.

**Type:** `null or (positive integer, meaning >0)`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.kind` {#secrets-managed-name-kind}

`ca` mints a self-signed certificate and key together, and always
carries `ca.crt` and `ca.key` — together, because the certificate is
signed by that key and generating them separately does not compose.

**Type:** `one of "value", "ca"`

**Default:** `"value"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.managed.<name>.store` {#secrets-managed-name-store}

Which declared store holds this secret's keys.

**Type:** `string`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores` {#secrets-stores}

Where this lab's authored secrets live.

**Type:** `attribute set of (submodule)`

**Default:** `{ }`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.backend` {#secrets-stores-name-backend}

Where this store's keys live.

`sops`: an encrypted file at `secrets/<lab>/<store>.enc.yaml`.
`env`: one environment variable per key, named
`CATA_SECRET_<STORE>__<SECRET>__<KEY>` — uppercased, with every
character that is not a letter or digit replaced by an
underscore. The name is derived, so there is nothing to declare
and nothing to keep in sync.
`vault`, `external`: held somewhere outside catallaxy.

**Type:** `one of "sops", "env", "vault", "external"`

**Default:** `"sops"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.direction` {#secrets-stores-name-direction}

Whether anything may write into this store at runtime.

`authored` stores are read-only and top-down: you write the value,
catallaxy decrypts it at deploy and projects it into every cluster
that needs it. A cluster cannot write back — for `sops` that would
mean committing to your repository.

**Type:** `one of "authored", "runtime"`

**Default:** `"runtime" for a vault or external backend`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.remover.command` {#secrets-stores-name-remover-command}

How to remove a value from this store, for when the thing that
produced it is destroyed.

Same contract as `writer.command` minus the value: it receives
`CATA_SECRET_KEY` and must exit non-zero if the key is still
there. A store with no remover is not an error — destroying a
stack says what it could not take back rather than refusing to
finish.

**Type:** `null or (list of string)`

**Example:**
```nix
[
  "vault-delete"
  "--mount"
  "lab"
]
```

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.vault.path` {#secrets-stores-name-vault-path}

KV mount path.

**Type:** `string`

**Default:** `"secret"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.vault.server` {#secrets-stores-name-vault-server}

Base URL of the vault-compatible server.

**Type:** `null or string`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.vault.version` {#secrets-stores-name-vault-version}

KV engine version.

An enum here though the CLI parses it as a plain string, because
writing a v2 mount as though it were v1 succeeds and stores the
wrong shape — which nothing notices until a reader gets an
envelope where it expected a value.

**Type:** `one of "v1", "v2"`

**Default:** `"v2"`

**Declared in:** modules/lab/secrets.nix

---
### `secrets.stores.<name>.writer.command` {#secrets-stores-name-writer-command}

How to write a value into this store.

It receives `CATA_SECRET_KEY` in the environment and the value on
stdin, and must exit non-zero if the write did not happen. Nothing
is passed on the command line, so a value never reaches a process
listing. This is what makes the set of backends open.

**Type:** `null or (list of string)`

**Example:**
```nix
[
  "vault-put"
  "--mount"
  "lab"
]
```

**Declared in:** modules/lab/secrets.nix

---
## `verify`

### `verify.endpoints.acceptStatuses` {#verify-endpoints-acceptstatuses}

Extra HTTP statuses that count as the endpoint answering.

A gateway that routes to a workload demanding auth answers 401, and
that proves the route works. 404 is deliberately not listable here:
it is what a gateway returns when it has *no* route, which is the
failure this check exists to catch.

**Type:** `list of integer between 100 and 599 (both inclusive)`

**Default:** `[ ]`

**Example:**
```nix
[
  401
  403
]
```

**Declared in:** modules/lab/types.nix

---
### `verify.endpoints.enable` {#verify-endpoints-enable}

Probe every publicly routed hostname the clusters expose.

The hosts and the paths come from `cluster.out.exposedHosts`, which
the elaborator reads off the rendered routes, so this needs no list
to maintain.

**Type:** `boolean`

**Default:** `true`

**Declared in:** modules/lab/types.nix

---
