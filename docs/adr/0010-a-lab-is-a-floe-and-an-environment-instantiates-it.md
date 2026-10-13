# A lab is a floe, and an environment instantiates it

`modules/lab/` is deleted. A lab is a `mkLabFloe` call that declares the
inputs its environments may vary; each `envs/*.nix` is one instantiation of
it. `mkLab` takes the instance and is the four phases outside it — link,
lower each cluster, plan, lower the lab.

This supersedes ADR 0009, which recorded 1,088 lines of option tree as the
floor. It was not one.

## Why 0009 was wrong

Three jobs were said to need the module system. Each had an answer.

**Merging a `lab.nix` with its `envs/*.nix`.** The argument was withdrawal:
`minimal/envs/talos.nix` writes `lib.mkForce null` to drop a cache its base
placed, and "argument defaulting cannot express withdrawal without the base
lab becoming a function of what each environment wants to remove". But the
base lab _is_ a function — of its inputs — and `units` is one of them. An
environment passes `units.registry = null` and the filter in `mkLabFloe`
removes it. The negation needed no merge, only a place to be written.

**The option reference.** This one was wrong on a fact, and the work that
made it wrong was already in the branch: "`name`, `zone`, `clusters` and
`units` are not any floe's inputs. There is nothing for a floe-interface
generator to read." If the lab is a floe they are exactly its inputs, and
they are `lib.mkOption` declarations in either shape — which is what
`49e278c`'s page generator reads. The objection was written before the thing
that removes it, and never revisited.

What survives of it is narrower and is now a gap rather than an argument: no
generator emits a page for an authored lab yet. The declarations are there
to read; nobody has written the reader.

**The cluster submodule.** `lab.clusters.<n>` was a 189-line submodule whose
two authored options were `floe` and `claim` and whose other ten were
`lowerCluster`'s results. A plain record holds the two, and the ten are
returned by the function that computes them.

## What the shape is

```nix
# examples/labs/minimal/lab.nix
catallaxy.mkLabFloe {
  name = "minimal";
  inputs = {
    zone.default = "minimal.test";
    cluster = lib.mkOption { type = catallaxy.floeInstance; default = clusters.app { }; };
  };
  units = _: { registry = floes.lab-registry { }; };
  clusters = { inputs, ... }: { app = { floe = inputs.cluster; inherit (inputs) claim; }; };
}

# examples/labs/minimal/envs/tls.nix
lab {
  name = "minimal.tls";
  cluster = clusters.app { tls = true; };
  units = { dns = floes.lab-dns { }; proxy = floes.lab-proxy { }; };
  verifyEndpoints.enable = true;
}
```

So what can differ between two environments is readable from the
definition's header. It was five files and a module merge.

A lab may **refine** a framework input rather than redeclare it —
`inputs.zone.default = "minimal.test"` — because the type and the prose
belong to `mkLabFloe` and only the default is this lab's. Redeclaring would
copy the paragraph that explains what a zone is into six labs.

## What had to be said in plain Nix

Three things the module system was doing for free.

**The step merge.** `lab.steps` has three producers and the module merge was
catching two of them claiming one name. It is also where every field a step
does not state gets its default. `stepTypes.mergeSteps` is an `evalModules`
over `declaredStepType` alone, so it keeps both — and `nix/option-docs.nix`
generates the schema page from that same module, which is what makes the
page unable to describe a field the merge would reject.

**The unit collision.** Framework units, cluster units, the author's and the
instantiation's are joined with `//`, and a collision replaces rather than
fails. A throw in `mkLabFloe` and not a policy, because a policy runs on a
link and by then one of the two is already gone.

**The assertion order.** The lab's assertions reach `metadata.json`, so the
order is in the digest — and the order the module merge produced was
alphabetical by the file each definition came from, not the order
`modules/lab/default.nix` listed its imports in. `tests/cloud.nix` is the
only lab with both a secret store and a plan assertion, so it is the only
one that noticed. Matched rather than refreshed: the order is arbitrary in
both worlds, and refreshing a digest for a harmless reason is how the next
refresh hides a real change.

## The two constructors, and what they share

`mkLabFloe` and `mkClusterFloe` are smart constructors over `mkFloe`, and
that is the right pattern for a distribution's conventions: an author writes
`policies = catallaxy.clusterPolicies` once or never, not in thirteen
cluster floes. What was wrong was that the two were _asymmetric_, and the
asymmetry was an artifact of the floe library rather than of the domain.

`inclusion.units` was a function of `{ inputs, requires, collects, floe }`
and `inclusion.defaults` was a plain attrset. A lab's defaults derive from
units that arrive as an input, so `mkLabFloe` had to rebuild its whole
definition per instantiation — and then needed a second throwaway `mkFloe`,
named `"<lab>-inputs"`, whose only job was to resolve the inputs before the
real definition existed. Both are fixed upstream: `defaults` takes the same
argument, and a `singleton` provider needs no entry at all because the
linker already refuses a second of one. `floes` commit `69f5c84`.

With that, both are `mkFloe` over a **frame** — the inputs every floe of a
kind has and the policies it is held to — and `mkClusterFloe` is nothing
else. `lib/floe-catallaxy/frame.nix` holds the pair and the three lines that
apply it.

Deliberately _not_ done:

- **No `mkComponentFloe`.** The 37 component floes share no inputs and take
  no policies, so it would be `mkFloe` renamed. The asymmetry is the
  domain's: a cluster has namespaces and a lab has an allocation.
- **No `kind` discriminator.** Three argument shapes behind one entry point
  reads worse than three functions.
- **No constructor over both.** `mkLabFloe` adds a body, so a shared
  constructor would need a hook for the difference — more machinery than the
  five lines it saves. A frame is data and `framedArgs` transforms
  arguments; that composes without hooks.
- **`clusters` stays its own argument.** It is derivable from `units` plus
  bindings — `placeCluster` finds the claim hole by signature, and
  `homelab.mesh` already binds a cluster floe — but folding it in means
  every lab hand-writes `.bind { claim = "app-claim"; }`, which turns
  `claimUnitFor`'s convention from something derived into something typed.
  And the pair _is_ the information: `minimal.talos` is a three-line diff
  because a cluster and its claim are written in one place.

## What stayed outside the floe

The lowering. A body cannot read its own units' link — that is what sealing
means, ADR 0007 — and linking, lowering each cluster, planning and lowering
the lab are all reads of it. So `mkLab` is those four phases over an
instance, and `lib/lower/link.nix` returns the link with the six folds every
reader of it shares.

Two kinds of fact the link cannot carry travel beside the instance, as
`instance.lab`: the clusters as _placed_, which is what the link was built
from, and the three inputs that are instructions to `cata` rather than to
any floe (`verifyEndpoints`, `secretsEnvFile`, and the resolved subnet).

## Consequences

**`mkLab` takes one argument and it is a lab.** `{ modules = [ … ]; }` is
gone, along with the `options` field of the record it returned.

**Discovery enumerates `envs/*.nix`.** Each is called with what a floe
definition is called with, plus the sibling definition as `lab`. A lab now
also has to answer to the name it was discovered under: `allocations.json`
is keyed by the discovered one while every host port and the subnet come
from the written one, so a mismatch moved a lab's whole allocation without
moving the row that recorded it.

**`mkCluster` is a function.** It drove one instance of the cluster
submodule by synthesising a whole `lab` record, which is a function wearing
a submodule.

**The option reference is the step schema and nothing else.**
`options/lab.md` is deleted and `cli/src/docs/options.rs`'s `Route` stops
being a prefix router.

**No manifest, plan, document, digest or address-plan entry moved** across
any of the twelve commits — including the two that replaced a hand-folded
singleton default with the linker's own. `minimal.tls` and `minimal.talos`
are what prove that replacement: `clusters.app` declares `optional.labCa`
and no lab names a provider, so a regression nulls the hole and moves their
digests.
