# Module Options

There is one, and it is not a lab's.

A lab is a floe and a cluster is a floe, so what either one takes is a
floe's `inputs` — passed as function arguments at the instantiation site,
not set on an option tree:

```nix
labs.minimal { name = "minimal.tls"; tls = true; }
```

That is why this section holds a single page. The option tree a lab used to
write against is gone; what replaced it is a declaration per module,
rendered from the module's own definition.

## Where a lab's options are

In its own `lab.nix`, as the `inputs` of a `mkLabFloe` call. The inputs
every lab has whatever else its author declares — `name`, `zone`, `units`,
`clusters`, `defaults` — come from `lib/floe-catallaxy/lab-floe.nix`, and a
lab may refine one rather than redeclare it:

```nix
inputs.zone.default = "minimal.test";
```

These have no generated page yet. That is the one gap the move from an
option tree to a declaration per module has left, and it is a generator to
write rather than a question to answer — the declarations are already there
to read.

## Where a floe's options are

On its own page under **Floes**. Each one carries two halves. The
**declaration** — inputs, requires, provides — is read off the floe
definition. What the floe **emits** — its bundles, its ops commands, its
lint checks — is read off an actual link, because an ops command's name is
not knowable until elaboration folds in the bundle it sits on. No header
could state it, and one floe documented an ops command under the wrong name
for as long as the page did not exist.

## The one page that is here

| Page                                   | Holds                                                      |
| -------------------------------------- | ---------------------------------------------------------- |
| [Plan Step Schema](./options/steps.md) | the fields a floe writes into its `LAB_STEPS` contribution |

It is here and not on a floe's page because it is not any one floe's: it is
the type every contributed step is checked against. `nixosOptionsDoc` runs
over exactly the module `lib/eval/step-type.nix` exports and the merge uses,
so the page cannot describe a field the merge would reject.

What a given `kind` accepts in its `params` is a different document —
[Plan Step Kinds](./step-kinds.md) — because the kind decides that, and the
kinds live in the CLI.

Regenerate with:

```bash
nix run .#refresh-docs
```
