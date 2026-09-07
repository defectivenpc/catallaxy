# catallaxy

**Declarative Kubernetes platform management.** A lab is a typed, ordered
graph of modules: the clusters, the capabilities running on them, and the
plan that builds all of it, expressed in the Nix module system and executed
by a Rust CLI.

The name is Hayek's, for the order that emerges when independent actors
follow their own rules rather than a central plan. It is the same claim
functional programmers make about **local reasoning**: if every part can be
understood on its own, composing them is safe and the global structure need
not be authored by hand.

So no part here knows the deployment plan. Each declares its own inputs, the
manifests it emits, and the capabilities it needs, and the install order is
_derived_ from those declarations rather than typed as a sequence of
numbers.

> **Built on RFC 0001.** The floe interface is
> [RFC 0001](docs/rfcs/0001-floes.md) (`lib/floe-core/`), and the shipped
> tree runs on it: nine example labs, 37 floes, host DNS, the registry, the
> proxy and secrets. Two earlier implementations preceded this one; what
> they cost is recorded in
> [`docs/prior-implementations.md`](docs/prior-implementations.md).

**[Documentation](https://onepunchtech.github.io/catallaxy)**

---

The unit is a **floe**: a typed interface with an implementation behind it.
It declares the capabilities it needs by name, and the linker finds whatever
provides them.

```nix
lab.clusters.core.floes = {
  cluster      = floes.k3d-cluster  { name = "core"; instanceName = "homelab-core"; };
  cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
  gateway      = floes.gateway      { chart = "${cataCharts.traefik.chart}"; };
  forgejo      = floes.forgejo      { chart = "${cataCharts.forgejo.chart}"; oidc = true; };
};
```

What is **not** there is the argument. Nothing says `forgejo` comes after
`gateway`, nothing passes the gateway's address into it, and nothing names
an issuer. `forgejo` declares `requires.gateway = sigs.API_GATEWAY`; exactly
one floe in that cluster provides it, checked at evaluation, and the
ordering edge falls out. No string templating, no values file duplicated in
two places, no sync-wave number chosen by looking at the neighbouring
numbers.

## Quick start

```bash
nix develop

cata-dev --flake ./examples/labs#minimal.local lab plan     # read it first
cata-dev --flake ./examples/labs#minimal.local lab up
cata-dev --flake ./examples/labs#minimal.local lab topology --format table
cata-dev --flake ./examples/labs#minimal.local lab verify

cata-dev --flake ./examples/labs#minimal.local lab destroy
```

`nix develop` gives you `cata-dev`, which runs the CLI from source. For the
released binary, `nix run .#cata`.

`minimal.local` is one k3d cluster with a gateway and one app (podinfo). It
runs no host ingress and no host DNS, so it comes up on any machine but is
not reachable from outside the cluster — `lab verify` checks it from within.
`minimal.tls` adds the proxy and a CA it mints; `homelab.local` adds
identity, observability and GitOps; `homelab.mesh` is reachable only from a
WireGuard mesh.

Walkthrough:
[Run the Example Lab](https://onepunchtech.github.io/catallaxy/start-here/first-lab.html).

## What it does

- **A plan you read before it runs.** `cata lab plan` prints the ordered
  step list `cata lab up` will execute: provisioning, host DNS and TLS,
  secret projections, cross-cluster copies.
- **Install order that is derived.** A floe says which capabilities it
  needs. Waves fall out. Nothing carries a number, and cross-floe ordering
  is not expressible by hand.
- **Failures that happen early.** Types, link errors naming both floes, lint
  over rendered manifests, and snapshot tests over the plan — none of which
  needs a cluster.
- **37 floes.** CNI, gateway, PKI, identity, observability, databases,
  registries, GitOps, backup, and yours built the same way, in your own
  repository. Each has a generated interface page under
  [`docs/floes/`](docs/floes/) that a check keeps honest.
- **Cloud clusters.** `doks` provisions a DigitalOcean cluster through
  OpenTofu ([RFC 0003](docs/rfcs/0003-resources.md)); `talos-cluster` and
  `external-cluster` cover bare metal and one you already have. A cluster
  elsewhere is its own edge, so the lab does not assume it can route to it.
- **Secrets that stay out of the store.** A credential is minted in the
  cluster that needs it, and moving one between clusters goes through a lab
  secret store rather than through Nix.

## Your own lab

Your flake takes catallaxy as an input; you never fork it. `examples/labs/`
is the worked reference, and CI builds every lab in it. See
[Build Your Own Lab](https://onepunchtech.github.io/catallaxy/start-here/your-own-lab.html).

## Development

```bash
nix develop                       # cata-dev, and every runtime tool
cargo build                       # the CLI
nix flake check                   # everything: tests, lint, snapshots, docs
nix fmt                           # nixfmt, rustfmt, yamlfmt
nix build .#docs                  # the book
```

`nix flake check` needs the sandbox permitted to fetch; an in-sandbox run
evaluates a stale tree and its green is not meaningful.

[Contributing](https://onepunchtech.github.io/catallaxy/contributing.html)

## License

[MIT](LICENSE)
