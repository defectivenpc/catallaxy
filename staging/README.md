# staging

`minimal.local`'s `app` cluster, composed out of floes on the interface of
[RFC 0001](../docs/rfcs/0001-floes.md). Four units, one `link`, one join,
and real YAML laid out in the order it has to be applied.

```bash
nix build .#staging-cluster-manifests && find result -name '*.yaml'
nix eval --json .#legacyPackages.x86_64-linux.stagingClusterMetadata.waves \
  --apply 'ws: map (w: map (b: b.name) w) ws'
```

## Why it is not in `floes/` or `examples/labs/`

It satisfies neither's contract. A floe under `floes/` is a NixOS module
declaring `options.floes.<name>` and registered in `floes/cluster/set.nix`;
these are `mkFloe` instances linked by signature. A lab under
`examples/labs/` is discovered by `lib/labs.nix` and must produce
`lab.out.cliConfig` and `lab.out.package`; this produces neither.

Both are auto-discovered, so a wrong-shaped file in either directory is a
failing check rather than a staging area. Hence a directory of its own, and
outputs named `stagingCluster` / `staging-cluster-manifests` rather than
`labs` / `labPackages` — those two names are what the CLI resolves, and it
is not going to change what it expects.

## The shape a floe author targets

Every cluster-component floe emits one output kind, `catallaxy.component`
(`lib/floe-catallaxy/component.nix`). It is `{ bundles; backs; }`, and a
bundle is where everything an author contributes goes: manifests in the
three shapes, a readiness probe, intra-floe ordering, ownership, images, and
the operator surface — `ops`, `lint`, `verify` — which sits on the bundle
rather than the floe because that is where the locality is (RFC 0002 §6). A
command about a workload can interpolate the namespace and the names of the
thing it is about.

**A bundle is not tied to one namespace, and a floe is not one bundle.** A
floe wrapping several charts emits several bundles, and one bundle may
install into several namespaces at once. Namespace is a property of each
resource and each chart, never of the bundle.

Absent on purpose: no `requires`/`provides`/`after`/`conflicts` token
strings. Ordering between floes "is not expressible here and must not be"
(RFC 0002 §5) — the elaborator derives every one of those. No
`prerequisites` channel either: it exists in the shipped tree only because a
bundle declared by two floes is a conflicting definition, and
exactly-one-provider already refuses a second provider by name. The Gateway
API CRDs are an ordinary unit here.

## The join is a monoid

`qualify` prefixes a unit's bundle keys with its name, so no two floes can
produce the same key and `//` is disjoint union. `empty` is a two-sided
identity, the join is associative, and it is commutative on disjoint domains
— all three asserted in `lib/tests/floe-cluster.nix`.

That is the difference from `lib/floe/fold.nix`, which is the closest thing
in the tree and has no production callers: `collectChannel` returns an
unrealised `mkMerge`, so it has no join of its own, no identity to name, and
its associativity is the module system's. The shipped tree has six different
merge mechanisms across eleven channels, one of which silently drops a
contested capability.

## bundles + link edges → cluster metadata

`lib/floe-catallaxy/elaborate.nix`. Core collects outputs keyed by unit and
does not merge them, which is what keeps the linker domain-agnostic; the
join belongs to the domain, and this is catallaxy's. Another domain writes a
different one against the same link result.

It joins, derives every ordering edge, lifts the operator surface, and hands
a bundle set to `lib/eval/manifest-graph.nix` — which is reused
**unchanged**, along with `manifest-autoedges.nix`, because the lowering
targets the token vocabulary those already read.

The derived order:

```
00  gateway-api/crds   namespaces
01  gateway/controller
02  gateway/gateway
03  podinfo/podinfo
```

Exactly one of those edges was written by anyone —
`gateway.needs = [ "controller" ]`, and even that names only a sibling in
its own floe. `podinfo` declares no ordering whatsoever. Its edge comes from
the link graph (it resolved `API_GATEWAY` to the gateway) crossed with the
gateway's `backs`, which says which of its bundles stand behind that
promise. Delete `backs` and the order survives: the default is all of the
provider's bundles, which is coarse but correct, so a floe that never writes
one still orders.

## What it proves against the shipped lab

Every rendered bundle is byte-identical to what `minimal.local` renders
today, once the ownership labels and the lab-scope image digest are
normalised away — and now in the same wave layout:

| Wave | Bundle                | Lines | vs `labPackages."minimal.local"` |
| ---- | --------------------- | ----- | -------------------------------- |
| 00   | `gateway-api__crds`   | 14353 | identical                        |
| 00   | `namespaces`          | 7     | identical                        |
| 01   | `gateway__controller` | 356   | identical                        |
| 02   | `gateway__gateway`    | 19    | identical                        |
| 03   | `podinfo__podinfo`    | 84    | identical                        |

`coredns-lab-dns` is the one reference bundle with no counterpart: it is
lab-scope, and this is a cluster.

## What is still missing

**Nothing provisions the cluster.** `out."catallaxy.cluster"` carries a k3d
descriptor whose field names track `ClusterSpec` in
`cli/src/domain/cluster.rs`, so lowering it later is a rename-free mapping.
Nothing reads it, and there is no state-based channel (RFC 0003), so nothing
creates a cluster.

**The CLI cannot consume this.** The wave directories are right;
`.wave-meta`, `.deploy-config` and `.declared-bundles` are not written yet.

**Channels the component does not carry**, each for a stated reason rather
than by omission: `steps` (its `params` is dependently typed on `kind`),
`infra.resources`, `secrets.generate`, `network` (netpol), and
`drift.expected` — `modules/lab/cluster/drift.nix:45-51` records that a
write-based aggregate for it deadlocks eval, so it cannot be a naive
channel.

**The next function is the lab one.**
`cluster metadata + link edges between clusters -> lab metadata`, in the
same shape as the one this round built.

## Sharp edges

**A floe input cannot be a derivation.** `instantiate` deep-forces its
inputs to check them eagerly, and `builtins.deepSeq` on a derivation does
not terminate — a derivation is a self-referential attrset. The failure is a
bare `error: stack overflow (possible infinite recursion)` before the floe
is ever linked. Pass `"${drv}"`; the string keeps its context, so a build
command interpolating it still gets a real dependency.

**`scanTokens` in `link.nix` has the same shape of problem.** It walks every
output attrset recursively looking for deferred tokens. A `resources` field
is typed `any`, so a derivation put in one — a ConfigMap sourced from a file
is the obvious way to hit it — makes the linker loop with no message. Kind
schemas here keep store paths as strings for that reason, but the guard
belongs in core: a derivation is opaque data and cannot contain a token.

**Sealing is enforced provider-side, and only there.** Deleting a field the
signature declares gives
`floe type error at gateway.provides.gateway.parentRef: missing field(s): sectionName`.
Reading a field the signature never promised gives a bare
`error: attribute 'zone' missing` naming neither the floe nor the signature
— `checkFloe`'s probe attrsets are item 6 of RFC 0001's implementation plan
and are not built.
