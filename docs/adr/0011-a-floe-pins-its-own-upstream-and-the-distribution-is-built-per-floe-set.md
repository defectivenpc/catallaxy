# A floe pins its own upstream, and the distribution is built per floe set

`lib/charts.nix` is deleted. A component carries `upstream.nix`: the repo,
chart, version and hash it vendors, and the extraction that yields its CRDs
if it has any. `lib/upstream.nix` keeps the combinators — how to pin one —
and knows which charts exist no longer.

`legacyPackages.withFloes` takes a floe directory and returns the
distribution rebuilt around it, so a floe outside this repository can
contribute API groups to the record its own floes are defined against.

## What was wrong with a registry

Three things, and the first two were live defects rather than arguments.

**It hid a duplicate.** `local-path-provisioner` and `openebs` were
byte-identical entries — same repo, chart, version and hash. Two names for
one chart, with the `openebs` floe using one of them and nothing using the
other. A table of names cannot tell you that two of its rows are one thing.

**It hid a pin with no owner.** `kanidm` was pinned and fetched for a floe
whose third line reads "No Helm chart." Likewise `cilium` and `argocd`
carried CRD extractions that no floe consumed, which the old
`floes/crds.nix` comment documented as deliberate — "nothing renders their
CRDs" — rather than deleted. A pin only a central table can hold is a pin
nothing has to claim.

**It let a floe reach another floe's pin.** `cataCharts` was the whole
table, handed to every floe. Nothing stopped `zot` defaulting its chart from
`cataCharts.harbor`. That is not a thing anyone did; it is a thing the shape
allowed, and the shape is what a check can hold.

None of this is expressible now. A duplicate is two floes, which
`floe-upstream` compares by chart derivation path and refuses. An unowned
pin has no floe directory to live in. A sibling's pin is not in scope:
`applyFloes` hands each floe `upstream`, which is its own pin and no
other's.

## Why the declaration is a file, not a `mkFloe` field

A floe states its holes and its outputs in `mkFloe`. Its CRD types cannot go
there, and this is the constraint that shaped everything else.

`crdTypes` is what `lib/floe-catallaxy` builds `kinds` and
`elaborateCluster` from. A floe is defined _against_ that record. So a
floe's types must exist before the floe can evaluate, and a declaration
inside `mkFloe` would be read only after it had. `mkFloe`'s argument set is
closed as well, but that is the smaller obstacle.

So the declaration is the directory's shape: `upstream.nix` yielding a
`crds` attribute means this floe's groups get generated into
`crds/<group>.nix` beside it. `lib/floe-crds.nix` reads it without
evaluating any floe — building an attrset forces no value, so the probe
passes a `throw` that fires loudly if anything reaches for a fetcher.

This also absorbed the per-floe `crds.nix`. It was one pin read twice, and
the second file existed only to signal "generate types for this floe" —
which a `crds` attribute says just as well, in the file that already holds
what they would be generated from.

## Why the distribution is built per floe set

The alternative was to accept a limit and document it, and that limit was a
silent wrong answer rather than a missing feature.

`mkFloes` closed over a `catallaxy` built from the built-in groups alone. A
consumer's CRD-bearing floe was therefore defined against a record with none
of its groups, so its custom resources resolved to no schema and were
checked for nothing. `conform.nix` says nothing when nothing describes a
kind — an `apiVersion` typo and a legitimately uncovered kind look identical
— which is the gap `crd-coverage` exists to close, and it cannot reach
across the repository boundary.

Parameterising the record is what makes the built-in set stop being special:
it is the set catallaxy ships, collected by the same function as yours. The
built-in distribution is `withFloes` of nothing, so for a consumer with no
CRD-bearing floes the result is identical to before.

The more elegant alternative — taking the types from whatever a link
contains — is circular. You would need the link to get the types and the
types to elaborate the link.

## Consequences

**A floe set is one namespace.** `floes` holds the built-in floes and yours
together, and a floe taking a built-in name is refused rather than merged,
because a link resolves `floes.<name>` against the merged set and a silent
override would mean a lab linking the floe it did not mean. The template's
`myFloes` is gone: your floes are reached as `floes.hello-world`, exactly as
a built-in one is.

**Generation is per floe.** `floeTypes.<floe>` regenerates one floe's groups
from that floe's artifact alone, and `generatedTypes` assembles those rather
than calling the generator again. The cost is real: the generator refused
two sources claiming one `group/Kind` because it saw every source at once,
and it now sees one. `floe-upstream` checks that instead, and names both
floes rather than failing on a merge.

**The combinators need no flake output.** An external `upstream.nix` is
handed `upstream` by the same `applyFloes` that hands it to a built-in one.
They also could not be the system-independent `lib.upstream` first planned —
they produce derivations, so they need `pkgs`.

**Three copies of `applyFloes` went.** Both doc generators, `floe-gates` and
`floe-names` each built the floe set themselves. Three of those copies were
already wrong — passing `cataCharts`, which no floe reads, and omitting
`upstream`, which every floe with a chart does — and nothing failed, because
a `defaultText` is a string and the default behind it is never forced.

The whole move was byte-neutral: 14 manifest digests, 15 cli-configs, the
plan snapshots, the allocation table and all 16 generated type files are
unchanged. That is what says 26 pins were transcribed rather than retyped.
