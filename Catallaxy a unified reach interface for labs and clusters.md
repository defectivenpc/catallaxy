# Catallaxy: a unified reach interface for labs and clusters

Nov 16, 2026 · @Michael

Yes: a lab and a cluster can offer one interface, **reach**, that says
everything a consumer needs to use them: which names resolve where, which
addresses route where, which roots to trust, and which credentials to use.
The host work you built (resolver, routes, trust store) then becomes one
consumer of that interface, an **attachment**, instead of code that knows
how a k3d lab on Colima is laid out. A parent lab, a CI runner or a
teammate's laptop attach the same way.

This note works from the repo as of commit `14f32ed`. It builds on the
mapping and realizer ideas from the earlier design doc but does not depend
on them landing first.

## What host integration does today

Five concerns, each split between a Nix floe that knows _what_ and CLI code
that knows _how on this machine_. Every one of them assumes the lab runs on
the operator's own machine, which is why remote Docker would break all four
at once.

| Concern     | Nix side (what)                                                             | CLI side (how, here)                                                                                                                                                     | Assumes the lab is local because                               |
| ----------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| Names       | `lab-zone` (`DNS_ZONE`), `lab-dns` (Knot, collects `HOST_EXPOSURE`)         | `host/dns.rs`: systemd-resolved drop-in or macOS `/etc/resolver` file, with sudo                                                                                         | The resolver is at a loopback port, or the Colima VM's address |
| Ingress     | `lab-proxy` (HAProxy, collects each cluster's hostnames and `CLUSTER_EDGE`) | Published on loopback ports from `lib/allocation.nix`                                                                                                                    | A browser on this machine dials 127.0.0.1                      |
| Routes      | `LAB_NETWORK` (a Docker network, one /20 per lab)                           | `host/network.rs`: Colima VM forwarding plus a host route to the subnet, with sudo                                                                                       | The Docker bridge is on this machine or its VM                 |
| Trust       | `lab-ca` (`LAB_CA`)                                                         | `host/pki.rs` mints the root and signs the ingress cert; `ensure_host_trust` adds it to the keychain or system store with sudo; `import_lab_ca` copies it into a cluster | The root's key sits in `~/.local/share/catallaxy/labs`         |
| Credentials | `SyncKubeconfig` steps                                                      | Kubeconfig per lab under the state dir                                                                                                                                   | The API servers are reachable from here                        |

There are already **two attachment modes**, side by side:

- **System-wide, with sudo:** resolver file, host route, trust store. Every
  tool on the machine sees the lab.
- **Session-scoped, no sudo:** `lab-egress` (a forward proxy inside the lab
  network), `io/egress.rs`, `io/trust.rs`'s merged bundle, and
  `cata lab env`, which prints `KUBECONFIG`, the CA bundle and the proxy as
  environment variables. Its own header says it: "Reaching lab hostnames
  from the host, without touching the host."

That second mode is the seed of the idea. It already treats the host as a
consumer that is handed values, not a place that is configured by code that
knows the lab's layout.

## The interface: reach

One signature that a cluster exports and a lab exports, with the same shape,
holding data and never effects:

```nix
REACH = floe.mkSig {
  name = "REACH";
  description = "Everything a consumer needs to use this lab or cluster from outside it.";
  fields = {
    names  = T.listOf (T.record { zone = T.dnsName; resolver = T.endpoint; });
    routes = T.listOf (T.record { subnet = T.str; via = T.endpoint; });
    trust  = T.listOf (T.record { name = T.str; certKey = T.str; });
    access = T.listOf (T.record { cluster = T.k8sName; kubeconfigKey = T.str; });
    egress = T.nullOr T.endpoint;
  };
};
```

- **names**: which zones exist and which resolver answers each.
- **routes**: which subnets exist and the endpoint that forwards to them.
- **trust**: which roots to trust, as lab store keys holding the public
  certificate. Never key material.
- **access**: which API servers exist, as store keys holding kubeconfigs,
  the same channel publication and subscription already use.
- **egress**: a proxy inside the lab, for consumers that will not touch
  their host.

Three properties make it the unifying piece rather than one more signature:

1. **It is a monoid.** A lab's reach is the union of its clusters' reaches
   plus its own host services' contributions. That is a collector, the same
   shape `lab-dns` and `lab-proxy` already use for `HOST_EXPOSURE`. The
   empty reach is a lab that offers nothing, which is today's ADR 0007 lab.
2. **It crosses boundaries only by export.** A parent lab that includes a
   child decides whether to re-export the child's reach. Sealing works
   unchanged: an operator attached to regional sees local-mgmt only if
   regional says so.
3. **Endpoints are relative to the substrate, not to the operator.** A reach
   says "the resolver is on port 5353 of the host this lab runs on". The
   substrate (`CONTAINER_HOST.address` in the mapping design) says where
   that host is from the operator's side: `127.0.0.1` locally, an address or
   an SSH tunnel for remote Docker, a mesh address for a netbird lab. The
   attachment composes the two, so nothing in a lab is written twice for two
   vantage points.

## Attaching: the consumer side

An attachment is a pure function from a reach to actions, given where the
consumer sits and how invasive it may be:

```rust
pub struct Vantage { substrate: SubstrateAddress, via: Path }   // direct, SSH tunnel, mesh
pub enum Mode { System, Session }

pub fn attach(vantage: &Vantage, mode: Mode, reach: &Reach) -> Saga<AttachAction>;
```

The per-OS code you already wrote does not go away; it becomes the adapters
behind those actions. What changes is that nothing in it reads a lab's
layout any more.

| Reach field | System mode (sudo)                                          | Session mode (no sudo)                            | Undo, from the receipt        |
| ----------- | ----------------------------------------------------------- | ------------------------------------------------- | ----------------------------- |
| names       | Resolver drop-in or `/etc/resolver` file (`host/dns.rs`)    | Nothing: the egress proxy resolves inside the lab | Remove the exact file written |
| routes      | Host route to the subnet (`host/network.rs`, `io/route.rs`) | Nothing, or an SSH tunnel for remote Docker       | Delete the exact route added  |
| trust       | Keychain or system CA directory (`io/trust_store.rs`)       | Merged bundle in env (`io/trust.rs`)              | Remove the certificate added  |
| access      | Context merged into `~/.kube/config`                        | `KUBECONFIG` in env                               | Remove the context            |
| egress      | Not needed                                                  | `HTTPS_PROXY` in env (`io/egress.rs`)             | Unset                         |

What this buys:

- **`lab up` stops needing sudo.** Bringing a lab up and attaching this
  machine to it become two verbs. `cata lab env` is already session attach;
  `cata lab attach --system` would be the other mode, and `detach` its undo.
- **Teardown removes what was added, not what is guessed.** `dns_teardown`
  today removes by zone name. With receipts journaled in the lab record,
  detach removes the exact file, route and certificate it put there, which
  is the compensation rule from the action-trait design.
- **Many to many.** One machine can attach several labs (zones and
  allocations are already distinct per lab), and one lab can be attached by
  several machines, each with its own receipts.
- **A cluster can attach too.** `import_lab_ca` copying the root into
  cert-manager is a cluster attaching to the lab's trust; `coredns-zone`
  forwarding the lab zone is a cluster attaching to its names. Same reach,
  in-cluster adapters. That is how a child lab's clusters would trust and
  resolve a parent lab without new code paths.

## How it behaves per substrate, and when labs nest

The lab's reach is the same in every row. Only the vantage changes, which is
the point.

| Substrate              | Where the lab's endpoints sit | Operator's vantage   | System mode                                                                           | Session mode                                                              |
| ---------------------- | ----------------------------- | -------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Local Docker, Linux    | Docker bridge on this machine | Direct               | As today                                                                              | As today                                                                  |
| Local Docker, Colima   | Bridge inside the Colima VM   | Via the VM's address | Route via the VM plus VM forwarding (today's `host/network.rs`, now a vantage detail) | As today                                                                  |
| Remote Docker over SSH | Bridge on the remote box      | SSH                  | A route through the box, which must forward the lab subnet                            | One SSH tunnel to the egress proxy and the API servers; no route, no sudo |
| Remote, on a mesh      | Bridge on a mesh peer         | Mesh address         | Mesh routes the subnet                                                                | Egress proxy over the mesh                                                |

For remote Docker, session mode over one SSH tunnel is the simplest thing
that works, and it is the path I would build first. One fact to watch:
published ports bind loopback by design (the ADR 0007 consequences note
`dns` and `registry` binding every interface was a defect), so on a remote
box they are reached through the tunnel rather than by binding wider.

### Nested labs

- **Inclusion:** the parent's reach is its own plus whatever child reach it
  re-exports. An operator attaches once to the parent and sees what the
  parent chose to show.
- **Retrieval:** a child publishes its reach to a lab store key, the same
  way `doks` publishes a kubeconfig today; anything with access to that
  store can attach to it without the child's flake.
- **Trust across levels** is the one place nesting changes the content, not
  just the plumbing. Today a lab holds exactly one root because "two means
  two chains". If a child lab's root is an intermediate signed by its
  parent's, attaching to the parent's trust covers every child; if each lab
  keeps its own root, an operator attaches to each. That is a question for
  you below.

## The shape at a glance

&#91;embedded content: reach and attachment · 3 producers, 1 interface, 3
consumers\]

Everything left of the accent box is the lab's business and is the same on
every substrate; everything right of it is the consumer's, and is the only
place a machine's OS, sudo or network path matters.

## What it replaces

The downward signatures stay; reach is their outward face. What goes are the
outward pieces that each carry one slice of it, and the host steps inside
`lab up`.

| Today                                                                                             | Becomes                                                                                                                       |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `CLUSTER_EDGE` and `HOST_EXPOSURE` (the Review.md "cluster edge" item)                            | A cluster's `REACH`: the names it serves and its edge as an endpoint. `lab-proxy` and `lab-dns` collect cluster reach instead |
| `DNS_ZONE`, `LAB_CA`                                                                              | Stay as what members install against; `REACH.names` and `REACH.trust` are what consumers outside see                          |
| `dns-setup` / `dns-teardown` step kinds, `ensure_host_trust`, the host route in `host/network.rs` | Attach actions, run by `cata lab attach`, not by `lab up`                                                                     |
| `cata lab dns`, `cata lab env`                                                                    | `cata lab attach` / `detach`, with `--system` or the session default                                                          |
| `SyncKubeconfig`                                                                                  | The `access` field, published to the lab store                                                                                |
| `import_lab_ca`                                                                                   | A cluster attaching to the lab's trust, with an in-cluster adapter                                                            |

What stays as it is: `lib/allocation.nix`, the host services themselves
(`lab-dns`, `lab-proxy`, `lab-egress`, `lab-registry`), and the per-OS
adapter code, which moves behind the attach actions rather than being
rewritten.

## Open questions for Michael

My default guess is in brackets.

- [ ] **Should `lab up` ever attach the host itself, or is attaching always
      a separate verb?** \[Separate; session mode by default, `--system`
      when asked\]
- [ ] **Trust across nested labs: one independent root per lab, or child
      roots as intermediates under the parent's?** Intermediates mean
      attaching to the root lab covers everything below it. \[Intermediates
      under the root lab\]
- [ ] **Remote Docker: is session mode over one SSH tunnel acceptable as the
      first and default path?** \[Yes; system mode over remote later\]
- [ ] **Should reach carry typed non-HTTP endpoints (registry, git over SSH,
      Postgres), or are names plus routes enough?** \[Names plus routes for
      now\]
- [ ] **Is "reach" the right word?** It needs a CONTEXT.md entry.
      Alternatives: surface, access, front. \[Reach, with attachment for the
      consumer side\]
