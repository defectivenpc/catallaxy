# Contributing

For changing catallaxy itself. Read
[How It Works](./understanding/how-it-works.md) first — this page assumes
you know which of the three layers your change lands in.

```bash
git clone https://github.com/onepunchtech/catallaxy
cd catallaxy
nix develop
```

That gives you `cata` (the built CLI), `cata-dev` (builds and runs from
source), the Rust toolchain, mdBook, and every tool the CLI shells out to.

## The loop

```bash
cargo build                    # or `cata-dev <args>`
nix flake check                # the gate
nix fmt                        # treefmt: nixfmt, rustfmt, yamlfmt, prettier
```

`nix flake check` runs the CLI build, formatting, the pure-Nix fixtures,
every floe isolation check, per-lab lint and planner assertions, the plan
snapshots, and the book. It is not slow enough to skip.

| Changed                   | Run                                                            |
| ------------------------- | -------------------------------------------------------------- |
| a floe                    | `nix build .#checks.x86_64-linux.floe-<name>`                  |
| a graph or the planner    | `nix build .#checks.x86_64-linux.{plan,manifest}-graph`        |
| anything affecting a plan | `nix build .#checks.x86_64-linux.'plan-snapshot-<lab>-deploy'` |
| the CLI                   | `cargo test`, then `nix flake check`                           |
| docs                      | `nix build .#docs`                                             |

Refresh a snapshot after an intentional ordering change:

```bash
cata --flake .#<lab> lab plan --stable [--teardown] \
  > examples/labs/tests/plan-snapshots/<lab>.<direction>.expected.txt
```

Read the diff before committing it. A refresh that reorders something you
did not intend to touch is the check doing its job.

## Conventions

**Functional flavour.** Data structures plus operations over them, rather
than long imperative bodies. Functions are `In → Out` mappings over
well-defined types.

**One purpose per file, under about 1000 lines.** Every source file opens
with a header of at most five lines saying what it is for. If the header
would be a list, the module is not cohesive. A file reduced below the limit
may not grow back past it.

**Comments explain why, never what.** Identifiers say what. A comment earns
its place by recording a non-obvious invariant, a constraint, or a
workaround — and for a workaround, recording the symptom and the date of the
incident that motivated it is house style, not clutter.

**Types live beside the module that owns them.** A type consumed from more
than one place does not belong in a `let`.

**No import-from-derivation.** Nothing in the evaluation path builds
something and then imports its output; IFD would make evaluation require a
build. The generated Kubernetes schemas are committed for this reason.

### Rust

Only `io/` performs I/O: `Command::new`, `std::fs`, `env::var` and `reqwest`
appear nowhere else. `commands/` is thin glue — logic that accumulates there
cannot be unit-tested or reused.

Parse `nix eval` JSON into a typed struct at the seam (`io::nix::eval_lab`);
downstream code takes `LabSpec`, not `serde_json::Value`. A
`.pointer("/foo/bar")` chain means a type is missing at the edge.

`commands/` returns `anyhow::Result<T>` because the context is what the user
reads; domain and `io/` use the `CataError` enum so callers can classify.
Never `unwrap()` data from outside the process.

### Nix

The **stable public API** is what `flake.nix` puts under `legacyPackages`:
`labs` and `labPackages` (the two the CLI resolves), plus `charts`,
`clusters`, `floeInterfaces` and `labPlans` for reading by hand. Breaking
one needs a changelog note. `modules/`, `lib/eval/`, `lib/render/` and
`lib/floe-catallaxy/` are internal.

## Adding a built-in floe

[Write a Floe](./using/writing-a-floe.md) applies unchanged. The extra
obligations for one that lives here:

**Register it.** There is no auto-discovery — add the directory to
`floes/default.nix`. In-tree floes use the trailing-application idiom,
because `mkFloe` returns a module _function_ and the floe needs its own
captured module arguments:

```nix
{ config, lib, pkgs, cataCharts, k8sSpecs, k8sHelpers, ... }@__floeModuleArgs:
let inherit ((import ../../../../../lib/floe { inherit lib; })) mkFloe; in
(mkFloe { name = "<name>"; imports = [ ./options.nix ]; module = { cfg, ... }: { }; })
  __floeModuleArgs
```

**Pin the chart** in `lib/charts.nix` rather than taking one from elsewhere.
Set `chartHash` to a dummy value, build, and copy the hash from the mismatch
error. Add a `crd` attribute if the chart ships CRDs (`type` is `chart`,
`url` or `github`), and put the CRDs in their own bundle so consumers can
gate on them being established.

**Ship a test suite** at `floes/tests/<name>.nix`, built on
`floes/tests/support.nix`. Not optional, and enforced 1:1 by
`nix/checks/lib-tests.nix`. The harness stubs each required signature and
runs the real linker and elaborator, so a suite exercises what the lab will
do rather than an approximation of it.

**Regenerate the floe's interface page** with `nix run .#refresh-floe-docs`
and commit it, or its diff check fails.

## Docs

The book is mdBook. `mdbook serve` over `docs/book` works for the
hand-written pages, but shows no per-floe reference and no changelog: those
are spliced in at build time by `pkgs/docs.nix`.

```bash
nix build .#docs && open result/index.html
```

The 37 per-floe pages come from `docs/floes/`, which
`nix/floe-interface.nix` generates and 37 checks diff. `pkgs/docs.nix`
copies them in, derives an index and the `SUMMARY.md` nav entries from the
file list, and appends the repo's `CHANGELOG.md`. So adding a floe adds a
page and a nav entry with no edit to anything.

Two checks hold it. `book.toml` sets `create-missing = false`, so a
`SUMMARY.md` entry with no file fails the build rather than rendering a
blank chapter; and `checks.docs` walks the built HTML for links that 404,
which mdbook does not check. The option-page generator that used to sit
alongside this is parked — `pkgs/default.nix` records what is missing.

Prose is formatted by prettier and wraps at 76 characters. Put identifiers
containing an underscore in backticks: prettier normalises emphasis to
underscores, so a bare `id_tokens` in a paragraph containing italics
corrupts both.

**Keep the book small.** It covers the model, how the system works, and the
two things a user does. Prefer improving those pages over adding new ones; a
page earns its place by being something a reader repeatedly needs and cannot
get from the generated reference.

## Pull requests

- **Small and incremental.** A refactor moves code without changing
  behaviour; a behaviour change is a separate pull request.
- **`nix flake check` and `cargo test` green.**
- **New files under about 1000 lines.**
- **`CHANGELOG.md` under `[Unreleased]`** for anything user-visible.
- **Snapshot refreshes reviewed, not rubber-stamped.**
