# The option tree stops at identity and merge

> **Superseded by ADR 0010.** The floor recorded here was not one: the
> option tree went to zero, `modules/lab/` is deleted, and a lab is a floe
> whose environments are instantiations of it. Every one of the three jobs
> listed under **Why not zero** had an answer, and the second of them was
> wrong on a fact — see ADR 0010. What is still true is the first half: the
> dozen scalars that derived from one another are gone, and
> `catallaxy.hostContainerFor` and `catallaxy.allocationFor` are where that
> went.

`modules/lab/` is 1,088 lines, from 2,239. What is left of the option tree
is twelve authored options and a cluster submodule, and this records why
that is the floor rather than a stage on the way to zero.

## What came out, and what it was

The plan was a wrapper — `mkLabFloe` — that would compute the
`lab.name`-derived values before `instantiate`, because `checkInputs` has no
`config` and no input can default off another. It was never needed. **The
lab's name travels on `LAB_NETWORK`**, so every host floe answers its own
container name and its own port from the one place the scheme is written:

| was                          | is                                           |
| ---------------------------- | -------------------------------------------- |
| four `containerName` options | `catallaxy.hostContainerFor`                 |
| five port options            | `catallaxy.allocationFor`, in each floe      |
| `lab.network.gateway`        | `cidrFirstIP subnet`, in `lab-network`       |
| `lab.dns.zone` ×4 threadings | `requires.zone = DNS_ZONE`                   |
| `lab.egress.resolvers`       | `optional.resolver = HOST_RESOLVER`          |
| `lab.registry.upstreams`     | the floe's default                           |
| `lab.dns.out.dnsInfo`        | `catallaxy.dnsInfo`, the resolver's emission |
| three `enable` flags         | placing the floe                             |

## The line

> **A fact belongs on the floe unless more than one _lab-level_ reader needs
> it.** A `provides` does not leave the lab's link, so a fact the lowering
> and a cross-lab check both need cannot live only on a unit.

That is the whole of why `lab.zone`, `lab.zonePort` and `lab.network.subnet`
are options while the ports and container names are not. `subnet` is read by
`cliConfig` and by the two checks that refuse two labs whose ranges overlap;
`proxy.httpPort` is read by the proxy. Not an inconsistency — a different
question.

## Why not zero

Three jobs are left, and the module system is the right tool for each.

**Merging a `lab.nix` with its `envs/*.nix`.** Measured once as "no authored
lab uses merge arithmetic", and that was wrong in one specific way:
`minimal/envs/talos.nix` writes `lab.units.registry = lib.mkForce null` to
withdraw a cache its base lab placed, because talosctl takes machine config
and has nowhere to mount a containerd one. Placing a floe is how a lab says
it runs one, and _that has no negation_ — `lab.units` takes `nullOr` for
this and nothing else. Argument defaulting cannot express withdrawal without
the base lab becoming a function of what each environment wants to remove.

**The option reference.** `docs/generated/options/` is `nixosOptionsDoc`
over this tree, diff-checked, so a default that moves is a reviewed line.
The recorded plan was for `nix/floe-docs.nix` to generate it from declared
`inputs` instead — and that does not work: `name`, `zone`, `clusters` and
`units` are not any floe's inputs. There is nothing for a floe-interface
generator to read. Deleting the tree means hand-maintaining the reference
for the twelve options a deployer actually writes, plus deleting
`cli/src/docs/` and its tests. That is a loss with nothing on the other side
of it.

> Wrong, and the work that made it wrong was already in this branch when it
> was written. If the lab _is_ a floe then `name`, `zone`, `clusters` and
> `units` are exactly its inputs, and `49e278c`'s generator builds an Inputs
> table from `mkOption` declarations — which is what they are, in either
> shape. ADR 0010.

**The cluster submodule.** `lab.clusters.<n>` is two authored options merged
across files, which is the same job as above.

## Consequences

**`mkLab` returns a record**, not an evaluation:
`{ name, zone, subnet, clusters, units, link, services, cliConfig, package, deploymentPlan, teardownPlan, options }`.
Forty-one sites stopped spelling `.config.lab.out.cliConfig`. The module
system is still inside; it is no longer the shape a caller reads.

**ADR 0007's objection to a plain `mkLab` is retired, and its replacement is
narrower.** The objection was the dozen scalars deriving from one another.
None of those exists now. What remains is merge semantics and generated
documentation, neither of which a plain function provides.

**No manifest, plan, document, digest or address-plan entry moved** across
any of the seven commits.
