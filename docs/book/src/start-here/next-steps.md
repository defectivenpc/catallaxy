# Where to Go Next

You have a lab running.

## Understand it

- [The Model](../understanding/model.md): lab, cluster, floe, bundle, and
  the scope rule that catches everyone out once.
- [How It Works](../understanding/how-it-works.md): how a declaration
  becomes a cluster, how install order is derived, and why the framework
  works so hard to fail at evaluation rather than at apply.

## Extend it

Everything below is available to a lab in its own repository, with no change
to catallaxy.

**A floe** is the main event: a capability with options, a typed interface,
and install-order dependencies. → [Write a Floe](../using/writing-a-floe.md)

For everything else — `floes.custom.apps` for a few resources with no option
surface, `lab.steps` for work that is not applying a manifest,
`lab.ops.commands` for an operator runbook, `lab.lint.checks` for a rule
about your manifests — see [Configure a Lab](../using/configuring.md).

## Look things up

- [CLI](../reference/cli.md): every command and flag.
- [Module Options](../reference/options.md): every option, generated from
  the module declarations.
- [Glossary](../reference/glossary.md): including the words that are
  deliberately overloaded.

## If something is wrong

`cata lab lint` first, then `cata diagnose <cluster>`. `-v` on any command
prints the underlying nix and kubectl invocations, which you can run
yourself.

[Contributing](../contributing.md) if you want to fix it here.
