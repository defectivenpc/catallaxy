# mkFloe API

Declared by the `floes` flake input, a library in its own repository. The
distribution's sugar and catalogues are in `lib/floe-catallaxy/`.

```nix
catallaxy.floe   # mkFloe, mkSig, link, narrows, T — the library, plus this
                 # distribution's k8sName and its `behaviour` argument
catallaxy.sigs   # the signature catalogue
catallaxy.kinds  # the constructors a component is built from
```

## `mkFloe`

```nix
mkFloe { name, summary, inputs ? {}, requires ? {}, optional ? {},
         collects ? {}, provides ? {}, out ? {}, modules ? [],
         body ? null, singleton ? false }
```

| Argument    | Required | Type                   | Meaning                                               |
| ----------- | -------- | ---------------------- | ----------------------------------------------------- |
| `name`      | yes      | kebab-case string      | the floe's identity                                   |
| `summary`   | yes      | string                 | one line saying what it installs                      |
| `inputs`    | no       | attrset of `mkOption`s | what the deployer decides — native NixOS option types |
| `requires`  | no       | attrset of signatures  | exactly one provider each                             |
| `optional`  | no       | attrset of signatures  | zero or one; `null` when unwired                      |
| `collects`  | no       | attrset of signatures  | every provider, keyed by unit; may be empty           |
| `provides`  | no       | attrset of signatures  | what it offers back                                   |
| `out`       | no       | attrset of signatures  | what it emits                                         |
| `modules`   | no       | list of modules        | the body, with the module system's merge              |
| `body`      | no       | function               | the body, as a plain function; no `evalModules`       |
| `singleton` | no       | bool                   | whether two instances in one link is an error         |

The pattern is **closed**: an unknown key is an error. `summary` is
defaulted to `null` in the pattern and refused explicitly rather than left
out of it, so the pattern stays closed _and_ the author gets a message
saying what to write — Nix's own "called without required argument" says
neither.

### Three arities

The arity is a property of the **hole**, not of the signature, so the same
signature can be exactly-one for one floe and collected by another.

`requires` is exactly one, and a second provider is an error naming both.
`optional` is zero or one. `collects` is the fan-in: every provider in the
link, keyed by unit, and one eval edge per contributor.

An `optional` hole **resolves only when a deployer names the provider**, by
`.bind` or by the link's `defaults`. A provider merely being present wires
nothing, and a link holding an unnamed candidate for an optional hole is an
error that names it. That is the whole difference from an `enable` flag:
adding a floe to a cluster cannot change another floe's output behind your
back. Of the shipped floes, eight have an optional hole — grafana's OIDC is
the readable one — and the lab's `defaults` pays the naming cost once for a
whole link rather than once per consumer.

Resolved optional values land in `requires` beside the exactly-one holes, as
the value or as `null`, so a body wanting "the thing if it is there" reads
one place.

### What the body sees

Two forms, which the linker cannot tell apart: both normalise to
`{ provides, out }`.

**`modules`**, ordinary NixOS modules in the floe's own `evalModules`, for a
floe that wants merge inside itself. Every shipped catallaxy floe uses this
form:

| Path                          | Is                                                                  |
| ----------------------------- | ------------------------------------------------------------------- |
| `config.floe.name`            | the link's name for this instance                                   |
| `config.floe.inputs.<n>`      | what the deployer passed                                            |
| `config.floe.requires.<hole>` | the resolved, **sealed** value, or `null` for an unwired `optional` |
| `config.floe.collects.<hole>` | every provider's, keyed by unit                                     |
| `config.floe.out.<sig>`       | what you write                                                      |
| `config.floe.provides.<hole>` | what you write, sealed on the way out                               |

**`body`**, a plain function `{ inputs, requires, collects, floe }: …`, for
a floe that does not need that merge. It costs about 30% less to evaluate.
Nothing here uses it yet.

Either way there is no lab-scoped `config` and no ambient option tree. A
fact from outside the floe arrives through a signature or it does not
arrive.

Declaring `provides` in `mkFloe` _and_ defining it in the body is not
duplication: the linker resolves every hole from headers before any body
evaluates, which is what makes a link's wiring checkable without running
anything.

## `mkSig`

```nix
mkSig { name, canonicalName, description, fields, behaviour ? [] }
```

| Argument        | Meaning                                                          |
| --------------- | ---------------------------------------------------------------- |
| `name`          | the identity resolution keys on. Two sigs sharing a name collide |
| `canonicalName` | the name a hole or provide of it should be called by             |
| `description`   | one line                                                         |
| `fields`        | attrset of `T.*` schemas, or a bare `T` for an opaque one        |
| `behaviour`     | **this distribution's**; see below                               |

`canonicalName`, `description` and `summary` are all required, and all three
throw explicitly rather than being bare pattern arguments —
`builtins.tryEval` cannot catch "called without required argument", so the
requirement would otherwise be untestable.

`canonicalName` exists because a hole's name is the first thing a reader
sees, and before it, `provides.operator` bound four different signatures. A
check enforces the bijection across every floe.

**Resolution keys on `name`, not on identity.** That is why there are four
separate `*_OPERATOR` signatures — `POSTGRES_`, `IDENTITY_`, `REDIS_`,
`MESH_` — rather than one: a single `OPERATOR` would make cnpg and kaniop
two providers of one signature, and every lab holding both would fail to
link. The nominal distinction _is_ the mechanism.

`behaviour` is added by `lib/floe-catallaxy/prelude.nix` and is not in the
library. It names the runtime checks any provider of a signature owes.
Compatibility settles a provider's _shape_; nothing settles that whatever
answers `X509_ISSUANCE` actually signs anything. A signature does not carry
a test — it carries the obligation that a provider have one, by name,
discharged by a `verify.<name>` the provider already declares and
`cata lab verify` already runs.

## The type language, `T`

**Why there are two.** A value a deployer writes — a floe input — is
described by a native NixOS option type. A value that _crosses a floe
boundary_ — a signature field — is described by a floe data schema, `T`.
That is the whole rule, and both halves are enforced where they are used:
`mkFloe` refuses a `T` in `inputs`, and `checkValue` refuses a `lib.types`
in anything that crosses.

`lib.types` cannot do the crossing side, for three reasons:

- **Sealing drops, it does not error.** A provider may compute more than its
  signature promises; `T.record` returns only the declared fields.
  `lib.types.submodule` refuses the whole value instead.
- **Some schemas carry linker-visible meaning.** `T.deferred` makes a deploy
  edge, `T.derivedFrom` is withheld from a collection's own contributors. A
  NixOS type has nowhere to put either.
- **A NixOS type holds functions.** `merge`, `check`, `substSubModules` — so
  it cannot be serialized, and a schema here has to be inert data.

| Constructor                                   | Is                                                                     |
| --------------------------------------------- | ---------------------------------------------------------------------- |
| `T.str`, `T.int`, `T.bool`, `T.port`          | scalars                                                                |
| `T.url`, `T.dnsName`                          | scalars with a pattern                                                 |
| `T.package`                                   | a derivation, or the store path it coerces to                          |
| `T.enum`, `T.nullOr`, `T.listOf`, `T.attrsOf` | the usual combinators                                                  |
| `T.record`                                    | a fixed set of named fields                                            |
| `T.taggedUnion`                               | externally tagged; matches serde's default                             |
| `T.deferred`                                  | not known until after apply; the linker derives a deploy edge from one |
| `T.derivedFrom`                               | folded out of a collection; withheld from contributors                 |
| `T.moduleType`                                | a NixOS type, for a field that is a schema                             |

`k8sName` is **not** in that list. It lives in
`lib/floe-catallaxy/prelude.nix`, because it was the one thing making the
library's "knows nothing about Kubernetes" claim false. The prelude is the
library plus this distribution's own types, and it is what a floe actually
gets.

### What crosses a cluster boundary

There is no per-field locality marking. A `T.local` field used to become a
`throw` when the value crossed, so a consumer found out at read time; the
boundary now carries a **signature that simply does not promise the field**,
and the refusal happens at link with the field named.

A **cluster declares its own exports**, so what crosses is a signature the
author chose and a reader can see in the boundary's header. There is no
table.

The narrow form is a _projection_ of the full one, built with
`floe.project`, so the two cannot drift:

```nix
MESH_NETWORK_SHARED = floe.project {
  signature = MESH_NETWORK;
  fields = [ "managementUrl" "dashboardUrl" ];
};
```

It withholds `namespace` and `managementInternalUrl` — one names an object
in one cluster, the other an address only reachable inside it. The
projection keeps the full form's `name` deliberately, because resolution
keys on the name, so a consumer resolves against whichever provider its own
cluster has.

An **allowlist**, so a field added to `MESH_NETWORK` later stays inside
until someone says otherwise, and a field the signature does not have is
refused rather than narrowing to nothing. The library's `narrows` relation
then holds by construction rather than being checked after the fact.

Nothing a distribution added to its own `mkSig` travels through a
projection: core's argument pattern is closed, so `behaviour` does not
cross. That is the right answer rather than a gap — the runtime checks a
provider owes belong to whoever runs the thing, discharged in that cluster's
own link, and a boundary re-exporting a view of it runs nothing.

What this gives up is the table's power to refuse outright. A signature
describing something that exists in exactly one place sets
`mayExport = false`, which the linker refuses as an export naming the
signature and the inclusion. The floe interface's ADRs 0011 and 0012.

## Output signatures

`out` takes signatures, like everything else; there is no separate
output-kind constructor. This distribution emits four:

| Signature                | Carries                                      |
| ------------------------ | -------------------------------------------- |
| `catallaxy.component`    | bundles, ops, lint, images — the common case |
| `catallaxy.cluster`      | a cluster descriptor                         |
| `catallaxy.resources`    | state-based stacks                           |
| `catallaxy.publications` | values written into a lab secret store       |

A floe's _category_ is just which of these it emits. There is no
registration mechanism beyond that.

## Testing a floe

`floes/tests/support.nix` builds a stub floe per required signature, then
links **and elaborates** the result, so a suite exercises the real linker
rather than an approximation. One suite per floe, enforced 1:1.

A `checkFloe` that would check a floe in isolation was proposed. It was
never built, and this replaced it: checking against the real linker catches
what an isolated approximation cannot.

## Related

- [Write a Floe](../using/writing-a-floe.md): the guide.
- [Bundle Schema](./bundles.md): every field of a bundle.
