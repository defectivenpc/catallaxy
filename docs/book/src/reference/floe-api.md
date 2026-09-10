# mkFloe API

Declared in `lib/floe-core/`. The distribution's sugar and catalogues are in
`lib/floe-catallaxy/`.

```nix
catallaxy.floe   # mkFloe, mkSig, mkOutputKind, T
catallaxy.sigs   # the signature catalogue
catallaxy.kinds  # the constructors a component is built from
catallaxy.mkComponentFloe
```

## `mkFloe`

```nix
mkFloe { name, summary, inputs ? {}, requires ? {}, requiresOptional ? {},
         provides ? {}, out ? {}, modules ? [] }
```

| Argument           | Required | Type                    | Meaning                                               |
| ------------------ | -------- | ----------------------- | ----------------------------------------------------- |
| `name`             | yes      | kebab-case string       | the floe's identity                                   |
| `summary`          | yes      | string                  | one line saying what it installs                      |
| `inputs`           | no       | attrset of `mkOption`s  | what the deployer decides — native NixOS option types |
| `requires`         | no       | attrset of signatures   | exactly one provider each                             |
| `requiresOptional` | no       | attrset of signatures   | zero or one; resolves to `null` when nothing provides |
| `provides`         | no       | attrset of signatures   | what it offers back                                   |
| `out`              | no       | attrset of output kinds | what it emits                                         |
| `modules`          | no       | list of modules         | the body                                              |

The pattern is **closed**: an unknown key is an error. `summary` is
defaulted to `null` in the pattern and refused explicitly rather than left
out of it, so the pattern stays closed _and_ the author gets a message
saying what to write — Nix's own "called without required argument" says
neither.

`requiresOptional` replaced a `requiresMany` fan-in. Two things were wrong
with that: it carried no ordering, and it implied only the floe installing a
capability could render resources using it — which is not how Kubernetes
works, since a registered CRD is a primitive anyone may use. A floe now
ships a constructor and the consumer emits the resource into its own bundle.

### What the body sees

Each module in `modules` is evaluated in the floe's own `evalModules`, and
reads:

| Path                          | Is                                    |
| ----------------------------- | ------------------------------------- |
| `config.floe.inputs.<n>`      | what the deployer passed              |
| `config.floe.requires.<hole>` | the resolved, **sealed** value        |
| `config.floe.out.<kind>`      | what you write                        |
| `config.floe.provides.<hole>` | what you write, sealed on the way out |

There is no lab-scoped `config` and no ambient option tree. A fact from
outside the floe arrives through a signature or it does not arrive.

## `mkSig`

```nix
mkSig { name, as, description, fields }
```

| Argument      | Meaning                                                          |
| ------------- | ---------------------------------------------------------------- |
| `name`        | the identity resolution keys on. Two sigs sharing a name collide |
| `as`          | the canonical local name a hole or promise binds it under        |
| `description` | one line                                                         |
| `fields`      | attrset of `T.*` types                                           |

`as`, `description` and `summary` are all required, and all three throw
explicitly rather than being bare pattern arguments — `builtins.tryEval`
cannot catch "called without required argument", so the requirement would
otherwise be untestable.

`as` exists because a hole's name is the first thing a reader sees, and
before it, `provides.operator` bound four different signatures. A check
enforces the bijection across every floe.

**Resolution keys on `name`, not on identity.** That is why there are three
separate `*_OPERATOR` signatures rather than one: a single `OPERATOR` would
make cnpg and kaniop two providers of one signature, and every lab holding
both would fail to link. The nominal distinction _is_ the mechanism.

## The type language, `T`

**Why there are two.** A value a deployer writes — a floe input — is
described by a native NixOS option type. A value that _crosses a floe
boundary_ — a signature field, an output-kind schema — is described by a
floe data schema, `T`. That is the whole rule, and both halves are enforced
where they are used: `mkFloe` refuses a `T` in `inputs`, and `checkValue`
refuses a `lib.types` in anything that crosses.

`lib.types` cannot do the crossing side, for three reasons:

- **Locality is per field.** `T.local` marks a field that does not travel to
  another cluster, and the linker, `isUncrossable` and the generated floe
  pages all read it. A NixOS type has nowhere to carry it.
- **Sealing drops, it does not error.** A provider may compute more than its
  signature promises; `T.record` returns only the declared fields.
  `lib.types.submodule` refuses the whole value instead.
- **A NixOS type holds functions.** `merge`, `check`, `substSubModules` — so
  it cannot be serialized, and a schema here has to be inert data.

| Constructor                                   | Is                                                                                                                 |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `T.str`, `T.int`, `T.bool`, `T.port`          | scalars                                                                                                            |
| `T.url`, `T.dnsName`                          | scalars with a shape                                                                                               |
| `T.enum`, `T.nullOr`, `T.listOf`, `T.attrsOf` | the usual combinators                                                                                              |
| `T.record`                                    | a fixed set of named fields                                                                                        |
| `T.taggedUnion`                               | externally tagged; matches serde's default                                                                         |
| `T.local`                                     | **does not cross a cluster boundary**                                                                              |
| `T.deferred`                                  | a value not known until apply. No shipped signature declares one; the token half is live in `lib/render/infra.nix` |
| `T.moduleType`                                | a NixOS type, for a field that is a schema                                                                         |

`k8sName` is **not** in that list. It lives in
`lib/floe-catallaxy/prelude.nix`, because it was the one thing making core's
"knows nothing about Kubernetes" claim false. The prelude is core plus this
distribution's own types, and it is what a floe actually gets.

`T.local` is per field, not per signature. `KUBERNETES_CLUSTER`'s every
field is local, which is what makes the whole signature uncrossable;
`API_GATEWAY` mixes them, so a consumer in another cluster gets the portable
half and is refused the rest.

## `mkOutputKind`

```nix
mkOutputKind { name, description, schema }
```

An output kind is what a floe emits. This distribution registers four:

| Kind                     | Carries                                      |
| ------------------------ | -------------------------------------------- |
| `catallaxy.component`    | bundles, ops, lint, images — the common case |
| `catallaxy.cluster`      | a cluster descriptor                         |
| `catallaxy.resources`    | state-based stacks (RFC 0003)                |
| `catallaxy.publications` | values written into a lab secret store       |

A floe's _category_ is just which kind it emits. There is no registration
mechanism beyond that; RFC 0001 describes one, and it was never built.

## `mkComponentFloe`

```nix
catallaxy.mkComponentFloe args   # = mkFloe with two defaults merged in
```

Defaults `requires.cluster = sigs.KUBERNETES_CLUSTER` and
`out.component = kinds.component`, merged over rather than replacing, so a
floe needing a second cluster hole can still name one.

Both are plumbing: a check verifies the wiring exists, it does not believe
the author about anything. A constant a check _believes_ — `imagesComplete`
— stays written out in every floe even at 31 of 33. That is the rule for
deciding the next one.

## Testing a floe

`floes/tests/support.nix` builds a stub floe per required signature, then
links **and elaborates** the result, so a suite exercises the real linker
rather than an approximation. One suite per floe, enforced 1:1.

RFC 0001 proposed a `checkFloe` that would check a floe in isolation. It was
never built, and this replaced it: checking against the real linker catches
what an isolated approximation cannot.

## Related

- [Write a Floe](../using/writing-a-floe.md): the guide.
- [Bundle Schema](./bundles.md): every field of a bundle.
- RFC 0001 in `docs/rfcs/`: the design, with a status block naming what
  shipped and what was abandoned.
