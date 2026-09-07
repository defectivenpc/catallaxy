# Run the Example Lab

`minimal.local` is a single-cluster lab: one k3d cluster, a gateway with TLS
from a self-signed CA, and one application. It requires no cloud account.

Prerequisite: [Install](./install.md), then `nix develop`.

## What labs are here

```bash
cata --flake . lab list
```

Lab names are `<lab>.<env>`. The environment suffix is part of the name.
There is no lab called `homelab`.

## The deploy plan

`lab up` executes an ordered list of steps. `lab plan` prints that list
without executing it.

```bash
cata --flake .#minimal.local lab plan
```

Most of those steps are host-side: a DNS server, a TLS-terminating proxy, an
image cache. A lab includes host services, not only cluster state. See
[How It Works](../understanding/how-it-works.md).

## Validation

```bash
cata --flake .#minimal.local lab lint
```

`lint` checks your tools, your configuration, and the rendered manifests.
That last one catches cross-resource mistakes: a Service selector matching
no workload, a Secret reference that resolves to nothing, a custom resource
with no CRD. See [Lint Rules](../reference/lint.md).

## Deploy

```bash
cata --flake .#minimal.local lab up
```

The run requests `sudo` once, to point the host resolver at the lab's DNS
server and to install the lab CA into the system trust store. It then
creates the docker network, the service containers, and the k3d cluster.
Expect a few minutes on a cold image cache, much less afterwards.

`--up-to` halts after the last step of a given kind:

```bash
cata --flake .#minimal.local lab up --up-to=create-cluster
```

## Inspection

`topology` reports what the lab contains and how it is wired: host services
and their ports, clusters and their networks.

```bash
cata --flake .#minimal.local lab topology --format table
```

`--live` queries the clusters for status instead of reporting it as unknown.
`mermaid`, `json` and `dot` are the other formats, for pasting into a
document or feeding to a graph tool.

The application is served through the lab gateway over the lab's TLS:

```bash
curl https://hello.minimal.test
```

Several lab pieces make that request resolve: the DNS server answers the
zone, the proxy terminates TLS with a certificate signed by the now-trusted
lab CA, and the gateway routes to the Service.

`kubectl` operates normally against context `k3d-minimal-local-app`.

## Teardown

```bash
cata --flake .#minimal.local lab down      # stop, keep state
cata --flake .#minimal.local lab destroy   # delete everything
```

`destroy` executes the teardown plan, which `plan --teardown` prints:

```bash
cata --flake .#minimal.local lab plan --teardown
```

The teardown plan is short for a local lab. For a cloud lab it governs the
order in which provider resources are released, and releasing them out of
order orphans load balancers and volumes.

## Larger examples

`homelab.local` is a multi-cluster lab with Kanidm OIDC, the observability
stack, ArgoCD, and a self-hosted Forgejo. The commands are identical:

```bash
cata --flake .#homelab.local lab plan
cata --flake .#homelab.local lab up
cata --flake .#homelab.local lab ops idm init-user lab-admin
```

Its plan is correspondingly longer. The
[examples README](https://github.com/onepunchtech/catallaxy/tree/master/examples/labs)
describes what each example lab demonstrates.

## Next

- [Build Your Own Lab](./your-own-lab.md): defining a lab in your own flake.
- [The Model](../understanding/model.md): lab, cluster, floe, bundle.
- [How It Works](../understanding/how-it-works.md): how wave membership is
  computed.
