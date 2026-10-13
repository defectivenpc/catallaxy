# A lab is a floe, and what it exports is nothing

`modules/lab/link.nix` builds one `mkFloe` whose units are the clusters, the
claim that answers each, and the floes the lab holds itself. It declares no
inputs, no holes, no provides and no body. Every surface is empty, and that
emptiness is the content: **nothing crosses out of a lab**, because nothing
links labs.

So the point of it is the other half of an inclusion. A floe whose `units`
is a link seals them — only `exports` crosses — and the lowering therefore
cannot read into them.

## The five reads, and why they were not a smell

`modules/lab/` read `lab.out.link.provides` five times, and every one of
them was legal. A parent reading a unit's _declared export_ is the interface
working, not a reach-in. The previous round of this work called them
reach-ins and that was wrong.

What they were not is _declared_. A read keyed by cluster cannot be an
`exports` entry, because `exports` is a flat name-to-signature map, so no
header anywhere said those five reads existed. And the lowering writes
`or { }` beside every channel read it makes, so a read that stops resolving
defaults rather than throwing. That is the failure a seal prevents, and it
is quiet: `lab-routed-hosts-are-claimed` would have passed vacuously for
every lab in the tree.

Each read is now the thing that holds the fact emitting it, as an output
kind — which lifts through an inclusion unconditionally, keyed by the unit
that emitted it. That key is the cluster's name when a cluster emitted it
and the contributor's when a collector hands a fan-in back, which is the
same name the read used.

| was                                   | is                                             |
| ------------------------------------- | ---------------------------------------------- |
| `provides.<c>.exposure` → routedHosts | `lab-proxy` emits `catallaxy.routedHosts`      |
| `provides.<c>.delivery`               | `lab-delivery` emits `cd.perCluster.<c>`       |
| `provides ? ca` → the https port      | `lab.out.services`, which is what it publishes |
| `provides.<c>.exposure` ×2, in checks | the rendered document                          |
| `provides.<mgmt>.<provide>`           | the provisioned cluster's own descriptor       |

## The one thing only the linker knows

`modules/lab/planner/provisions.nix` reads
`wiring.optional.<claim>.provisioning` to find which cluster filled a
claim's hole. No collection and no output kind can answer it: a collector
gives every provider of `CLUSTER_PROVISIONING` keyed by contributor, which
says which clusters provision but not which claim each one resolved against,
and `mgmt` is a _unit name_ — a floe has no name for a sibling, and the
plan's anchors are keyed by cluster name.

So `wiring` is a declared channel beside the output kinds, and the line it
sits on is sharp: it answers "which provider filled this hole" and never
"what did it provide". The value that read used to need was already on the
provisioned cluster's descriptor, because `floes.external-cluster` writes
what its `provisioning` hole resolved to into
`config.external.provisionedBy`.

## Considered options

**A hatch to the inner link for the lowering.** The seal is then decorative,
and the honest version of that is not wrapping at all.

**`wiring` entries carry the value they resolved to.** One change in the
floe interface, and it would have made the provisioning read a single
lookup. Not taken: a wiring entry would then carry a value out of a sealed
unit, which is the seal with a general exception rather than a line.

**Not wrapping, and enforcing the channels by check alone.** The check is
here either way. What the wrap adds is that a new read of `provides`
resolves to nothing instead of to an export — so the check is the diagnostic
rather than the only thing standing between the tree and a silent `or { }`.

## Consequences

**No manifest, plan, document or digest moved.** The whole of ADR 0006's
output is byte-identical with the lab as a floe, which is the evidence that
the seal was already respected once the five reads were gone.

**Two defects fell out of the reads moving.** `lab-host-ports` decided
whether a lab binds 443 with `link.provides ? ca`, which tests for a _unit
named_ `ca` — a lab placing its root under any other name published the port
and claimed nothing. Reading `lab.out.services` instead also found that
`dns` and `registry` publish bare `5353:53` with no address, so they bind
every interface rather than loopback, and that a resolver claiming one port
on tcp and udp is not a container binding it twice.

**`routedHosts` means something different, deliberately.** It was every
cluster's exposure regardless of whether the lab ran an ingress; it is now
the ingress's account of the `use_backend` rows it wrote. A lab with routed
workloads and no proxy listed hostnames nothing answered for, and
`cata lab verify` refused it for publishing no ingress port to reach them
on. Two fixtures lose their entries and `endpoints` reports those hosts as
not probed, with the reason.

`lab-routed-hosts-are-claimed` follows the same line and loses coverage with
it: a lab with no ingress is no longer checked. The fault it looks for does
not bite there — nothing on the host reaches a claimed route either.

**The prefix strip is real and has to be exact.** An instance has no `out`
and no `provides`; only `link` evaluates a floe. So the lab floe must be
linked as a unit of something, and everything it lifts is qualified
`<lab>/`. Three channels carry unit names and all three are stripped —
including the `instName` and `backedBy` fields _inside_ wiring entries,
which `lib/floe-catallaxy/slice.nix` shortens for the same reason and which
the plan caught immediately when they were missed. A `/` in a lab's name is
refused, because that is the one character that would make the strip
ambiguous.

**A pure inclusion with nothing declared is legal**, and worth recording as
something the floe interface permits on purpose: `floe.nix` refuses
`exports` without `units` and `provides` with nothing to define them, and
says nothing about a floe that promises nothing at all.
