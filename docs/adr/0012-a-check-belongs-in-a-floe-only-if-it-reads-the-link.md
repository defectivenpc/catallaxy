# A check belongs in a floe only if it reads the link

A rule about an evaluated link is a **policy** — `clusterPolicies` or
`labPolicies`, declared by the distribution and run by `link.nix` over the
link result. A rule about anything downstream of the link stays in
`nix/checks/`.

`crdsResolveToASchema` is the first one moved under this rule.
`crd-coverage` was a check over every lab; it reads
`result.out."catallaxy.component"` and nothing else, so it is a cluster
policy, and the cluster that renders an unschema'd resource is now refused
where it is linked.

## The question that decides it

Not "is this about a floe" — nearly every check is. **What does it read?**

A policy receives the link result: `provides` (every sealed provide's
value), `out.<kind>` keyed by unit path, `inputs`, `wiring`, `floeNames`,
`graph`, `cycles`. That is a lot, and it is the reason this rule has to be
stated rather than assumed — a policy can see across a cluster seal, because
`out` lifts unconditionally, so cross-cluster laws are expressible.

What a policy cannot see is everything that exists _after_ linking:

| it reads                        | example                                      | why not a policy                      |
| ------------------------------- | -------------------------------------------- | ------------------------------------- |
| the lowered document            | `lab.cliConfig.routedHosts`                  | lowering runs after the link          |
| the built package               | `yq` over `lab.package/manifests`            | a derivation, not an evaluation       |
| a file on disk                  | the secrets env file                         | a path, parsed                        |
| the repository                  | `docs/generated/`, prose, the floe catalogue | a floe has no repository              |
| an assembly that must not exist | a bent lab asserted to be refused            | if it is refused it does not evaluate |

## Why the ones that stay, stay

Three cases are worth recording, because each looks movable and is not.

**`lab-routed-hosts-are-unique` reads the lowered document on purpose.** Its
own comment is the argument: it "read each cluster's exported exposure,
which is the same set only while the fold between them is right." It checks
the document HAProxy is configured from so that it does not re-derive the
fold. A policy would reintroduce the derivation that was wrong.

**`images-*` is empirical.** `floe-gates` scrapes images out of rendered
YAML with `yq` and compares them to the floe's claim. The claim is a
declaration and the evidence is a built artifact; only a derivation can hold
both. This is the same reason chart values are checked by render-diff.

**`lab-subnets` and `lab-host-ports` are about a _pair_ of labs.** Each lab
is correct on its own in every case; the fault exists only in the set of
labs this repository builds, and no link is a member of that set. They live
in `nix/checks/across-labs.nix`, where the filename answers the question.

## Why not push the repository into reach

A floe that read `docs/generated/` or the floe catalogue would be
unbuildable outside this repository. ADR 0011 made the built-in set stop
being special — "it is the set catallaxy ships, collected by the same
function as yours" — and a floe that depends on this repo's tree takes that
back. The asymmetry is not a gap: a consumer's floe is held to the same
policies ours are, and neither is held to our committed files.

## Consequences

**`labPolicies` and `clusterPolicies` are where a lab-wide or cluster-wide
law goes.** An eval-time refusal naming the offending unit beats a repo-wide
check listing findings across fourteen labs, and it fails the lab that is
wrong rather than the suite.

**`nix/checks/` is not a backlog.** After this rule, what remains there is
there because of what it reads: staleness diffs over committed generated
trees, grep laws over prose and `lib/`, laws quantified over the whole floe
catalogue, empirical checks over built packages, and negative cases about
assemblies that must not exist. None of them is waiting to become a floe.

**A new check asks the question first.** If it reads only the link result,
it is a policy and belongs in `lib/floe-catallaxy/domain/policies.nix`. If
it reads a document, a package, a file or the tree, it is a check.
