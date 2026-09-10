# RFC 0004 — Appliances: what a lab runs for itself

Status: **Not built.** Scope: one of the delivery categories a floe can
declare. Depends on RFC 0001, sibling to RFC 0002 and RFC 0003.

> **What shipped instead.** No `appliances` category exists, and no `run`.
> The word "appliance" appears nowhere in the source tree. A lab's host
> services are **four fixed options** — `lab.{dns,registry,proxy,egress}` —
> declared by the lab module in `modules/lab/host/` and
> `modules/lab/network/dns.nix`, aggregated into `lab.out.services`, and run
> by `cli/src/host/services.rs`. RFC 0005 §1.1 concedes the point from the
> other side: an appliance is not a floe, so `lab.dns` is an option surface
> rather than a signature.
>
> What of this RFC _is_ true of the tree:
>
> - **§3** — a change to an appliance's configuration is a change to the
>   appliance. Built precisely: `services.rs` compares rendered volume
>   content and the image, and recreates the container on either.
> - **§6** — providing without running. Shipped, but one level up and for
>   _clusters_: `floes/provisioners/external-cluster.nix` provides
>   `KUBERNETES_CLUSTER` and creates nothing. For DNS itself,
>   `lab.dns.enable = false` still yields `lab.provides.zone`, so a consumer
>   genuinely cannot tell — §6 built via an option rather than via two
>   floes.
> - **§8.2** — one host, several labs. Answered: `nix/checks/lab-checks.nix`
>   refuses two labs claiming one host port or overlapping docker subnets,
>   across every lab at once.
>
> What is not:
>
> - **§4** — "ordering comes from requirements, not from a lifecycle table".
>   `modules/lab/plan.nix` opens with a lifecycle table. Resolving
>   `DNS_ZONE` creates no ordering edge, and `lib/floe-core/link.nix` says
>   why: a scope provider is not a node in that graph.
> - **§9.7** — "no edit to a registry, an aggregator, a port table". All
>   three exist: the imports and `lab.out.services` in
>   `modules/lab/host/default.nix`, and `portsOf` in
>   `nix/checks/lab-checks.nix`.
> - **§2's `ops`, `verify` and `backedBy` on an appliance.** None exists;
>   host-service verification is hard-coded in `cli/src/verify/checks/`.

A lab needs infrastructure of its own: name resolution for its zone, an
image cache, a way in, a way out. This RFC defines how a floe declares one.

## 0. What this category supplies

This RFC describes an **appliances** delivery category. RFC 0001 defines no
category-registration mechanism, and this category was never built — see the
status note above. The four parts:

| Part         | Is                                                     |
| ------------ | ------------------------------------------------------ |
| `memberType` | `run`, `ready`, `needs`, and the operator surface (§2) |
| `target`     | the host the lab is operated from                      |
| `done`       | its readiness probe (§2)                               |
| `nodes`      | one node per appliance                                 |

## 1. What an appliance is

**Fixed-function, configured, serving.** A resolver answers for a zone. A
registry caches images. An ingress proxy routes hostnames to backends. Each
does one job, is configured rather than programmed, and once running is
simply available. That is what an appliance is, and the word is meant
literally.

Three properties follow from that, and between them they are the whole
design.

**An appliance is a process, so the question is whether it is up.** Not
whether it exists, not whether it matches a recorded shape — whether it is
serving right now. It can restart. It can log. It can crash-loop and come
back. Readiness is a routine question asked constantly, rather than a
one-time gate.

**An appliance belongs to the lab, not to a cluster.** One resolver answers
for every cluster in the lab. Putting it inside a cluster would make
creating a cluster depend on a cluster, and would give the second cluster
nothing.

**An appliance brackets cluster lifetime.** Name resolution and an image
cache have to be serving before the first cluster is created, and they are
still serving after the last one is destroyed. Their lifetime contains,
rather than follows, the lifetime of the things that use them.

## 2. What an appliance declares

```nix
appliances.resolver = {
  run = oci "cznic/knot:3.4.6" {
    ports    = [ "${toString config.port}:53/udp" ];
    networks = [ uses.lab-network.values.name ];
    files."knot.conf" = config.generatedConfig;
  };

  ready = ready.dns config.zone;
};
```

| Field    | Meaning                                       |
| -------- | --------------------------------------------- |
| `run`    | what to run, and how                          |
| `ready`  | the predicate that decides it is serving      |
| `needs`  | sibling appliances that must be serving first |
| `ops`    | commands the operator may invoke against it   |
| `verify` | checks against the running appliance          |

Readiness and the operator surface sit beside the thing they are about, and
`needs` names siblings directly rather than through a shared namespace — the
same locality argument RFC 0002 §6 makes, for the same reason.

**An appliance may be named in `backedBy`.** RFC 0002 §7 defines `backedBy`
as naming the deliverables whose readiness is the capability's readiness;
for an appliance-backed provision those are appliances, and they are nodes
in the same delivery graph (RFC 0001 §4.12).

**`ready` is not optional in practice.** An appliance with no probe is one
whose failure surfaces later and somewhere else, as a timeout in whatever
depended on it. The cheapest useful probe — does the port accept a
connection — is one line, and it converts a mystery into a named failure.

## 3. Configuration is part of what runs

Most appliances are a stock image plus a generated configuration file, and
the file is the interesting half: a zone, a backend map, an upstream list.
It is declared as part of `run` rather than as a separate concern, which has
one consequence worth stating outright.

> A change to the configuration is a change to the appliance.

Supervision compares what should be running against what is, and the
configuration is part of that comparison. Editing a zone restarts the
resolver, without anyone having asked for a restart and without a separate
reload mechanism to get wrong.

## 4. Ordering

**Within a floe**, `needs` names siblings.

**Everywhere else, ordering comes from requirements**, not from a lifecycle
table. An appliance backing a provision is serving before any consumer of
that signature proceeds. "The lab's DNS is up before the first cluster is
created" is therefore a consequence of something requiring `dns-zone`, not a
phase anyone wrote down.

This is where the pressure is. Lab-side infrastructure accumulates an
implicit sequence — network, then DNS, then registry, then certificate
authority, then clusters — encoded as an ordered list whose individual steps
nobody can justify. Under requirements each edge carries a reason, and an
edge with no reason is one that should not exist.

## 5. Teardown

An appliance stops when nothing requires it any more, in reverse order.

**Every appliance that starts needs something that stops it.** Lab-side
setup is where asymmetry accretes: a certificate authority left installed, a
host route left configured, a cache left warm. Some of those are deliberate
and should survive teardown. The ones that are deliberate have to say so,
because otherwise a step with no counterpart is indistinguishable from one
that was forgotten.

## 6. Providing without running

A signature does not require an appliance behind it. The same job can be
satisfied by a floe that runs something and by one that names something
already there:

```nix
# runs a resolver
floe local-dns {
  provides.dns-zone = {
    values   = { zone = config.zone; server = appliances.resolver.address; };
    backedBy = [ appliances.resolver ];
  };

  appliances.resolver = {
    run   = oci "cznic/knot:3.4.6" { ... };
    ready = ready.dns config.zone;
  };
}
```

```nix
# names one that already answers
floe existing-dns {
  provides.dns-zone = {
    values = { zone = config.zone; server = config.server; };
  };
}
```

The second runs nothing. It has no `backedBy`, so there is nothing to wait
for: the claim is that the zone is already served, and if it is not, that is
a misconfiguration rather than a race.

Consumers cannot tell the difference, which is the point (RFC 0001 §3.1). It
also settles what the built-in appliances are for. A local resolver and a
local registry are **defaults, not fixtures** — conveniences for a lab
standing on its own. A lab with DNS and a registry already in place
instantiates different floes providing the same signatures, and nothing
downstream changes.

## 7. What this is not for

**Not for anything a cluster could own.** If a controller can reconcile it,
it is a bundle. An appliance exists because there is no cluster yet, because
the thing serves several clusters, or because it is what the operator's own
machine has to run for the lab to be reachable at all.

**Not a general process supervisor.** The scope is what a lab needs in order
to function. A floe tempted to run a long-lived process for its own sake
wants a workload in a cluster instead.

## 8. Open questions

1. **How much of a container's shape to model.** Networks, published ports
   and mounted files are unavoidable. Host networking, added capabilities
   and pinned addresses are wanted by a minority — plausibly one appliance —
   and modelling them for that minority may be worse than leaving one escape
   hatch.
2. **One host, several labs.** Appliances from two labs share a machine, so
   ports and container names collide. Whether that is the model's problem or
   the operator's is undecided: a check that refuses a collision has to see
   both labs, and nothing does.
3. **Supervision depth.** Comparing declared against running is clearly in
   scope. Restart policies, log retention and health-driven restarts are a
   slope toward reimplementing a process supervisor badly.
4. **Where an appliance's data lives.** The host knows what is running, but
   a generated configuration file and any persisted data live somewhere on
   disk, and that location is a lab-level fact this RFC does not name.

## 9. How to evaluate this concept alone

1. A lab's DNS is a floe: it provides `dns-zone`, runs a resolver, and every
   cluster requiring that signature resolves to the one instance.
2. Swapping the local resolver for DNS that already answers changes one
   instantiation and no consumer.
3. An appliance's readiness gates the consumers of what it provides, with no
   lifecycle phase written down anywhere.
4. A floe whose configuration file changes is restarted, because the file is
   part of what is running.
5. Nothing a cluster could reconcile is expressed as an appliance.
6. Every appliance that starts has something that stops it, or says why not.
7. Adding a new lab-side appliance requires no edit to a registry, an
   aggregator, a port table, or any other central list.
