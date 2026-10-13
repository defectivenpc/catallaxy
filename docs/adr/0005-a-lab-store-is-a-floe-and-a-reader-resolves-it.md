# A lab store is a floe, and a reader resolves it

A store on the operator's machine is `floes.lab-secret-store`, providing
`LAB_SECRET_STORE`. One secret in it is `floes.lab-secret`, requiring a
store and providing `LAB_SECRET`. Both are units of the lab's link, placed
in `lab.units`, and everything that reads one resolves it.

What this closes is six places that named a store or a secret by string,
none of them checked by anything:

| site                                | was                         |
| ----------------------------------- | --------------------------- |
| `secret-projection`                 | `source = "<secret>"`       |
| `secret-store` (the in-cluster one) | `labStore = "<store>"`      |
| `doks`                              | `publishKubeconfigTo.store` |
| `provisioned`                       | `publishTo.store`           |
| `external-cluster`                  | `kubeconfigFrom.store`      |
| `lab.secrets.managed.<s>.store`     | `store = "<store>"`         |

The last one had an assertion comparing the string against the declared
stores — which is resolution, written out by hand, in the one place the two
tables happened to sit side by side. The other five had nothing. A typo in
`source` left a Secret `cata` had no values for, applied, with whatever
mounted it waiting forever on a key nothing would write.

Two signatures rather than one, because a projection does not want a store.
It wants _a particular secret_, and `LAB_SECRET` carries the key list so a
projection reading a key that secret does not hold is refused where the
projection is written rather than at `cata lab up`.

Not `SECRET_STORE`, which already exists and is the in-cluster `SecretStore`
CR an ExternalSecret reads from. Nothing about a lab store is in a cluster:
it is a sops file, a set of environment variables, or a vault somewhere
else, and the thing that opens it is the CLI. Same split as `OCI_MIRROR`
against `OCI_REGISTRY`, for the same reason.

## Considered options

**A check rather than a signature.** Walk every projection's `source` and
every publication's `store`, compare against the declared set, and refuse a
mismatch. Cheap, and it catches the same class. Rejected because it leaves
the floes naming each other through a namespace neither owns — a store's
_existence_ would be checked and nothing else, so `writable` stays a flag
beside the name and the graph still has no edge from a publisher to the
store it writes. The edge is the thing: `floes/tests/provisioned.nix` now
pins `eval:provisioned->stub-labStore`, which is a dependency the plan can
order against and a string could not be.

**`collects` on the reader, matched by an input name.** Would let one hole
serve any number of stores. Rejected because matching is string matching
with extra steps.

**Keep `lab.secrets.managed` and lift only the stores.** Rejected because
`source` is the larger of the two gaps and the one that silently applies a
broken Secret.

## Consequences

**`writable` stops being a flag.** It followed from the backend all along —
`sops` and `env` are read-only and top-down, `vault` and `external` are not
— but `secret-store` took it as an input beside its `labStore` string, so a
lab could call a vault-backed store read-only or a sops-backed one writable
and nothing would notice until a PushSecret never reconciled.
`checks.secret-sharing` used to bend exactly that; it binds the sops store
instead now, because saying it is no longer possible.

**A lab with several stores writes a `.bind` per reader.** One store and one
secret resolve for free, which is `minimal.secrets`, `homelab.dns` and
`cloud`. `every-floe` has three stores and two secrets and binds all five,
which is the ambiguity being real rather than ceremony — and it is the same
ceremony `lab.defaults.CNI_BOOTSTRAP` already is. `cloud` uses
`lab.defaults.LAB_SECRET_STORE` instead, because an optional hole's default
_is_ the decision to wire it and one line covers both sides of the
kubeconfig.

**A cluster floe declares what it reads of the lab's secrets.** Six of them
gained a line. That is the cost of a sealed boundary and it is the same cost
`requires.zone = DNS_ZONE` is.

**`lab.secrets` is down to `envFile`**, which is not a fact about any store:
it names one way to fill the environment several `env`-backed stores read
from, and it is a path in the repository rather than anything catallaxy
opens. The two assertion families that compared store and secret names are
gone with the names.

**The key crossing a publication is still written twice.** `doks` publishes
`clusters/workload/kubeconfig` and `workload`'s claim reads it, and neither
can derive the other's — the two clusters have different names. Only the
store is resolved. `PUBLISHED_SECRET` solved this for the in-cluster case by
having the producer name the key and provide it; doing the same here needs
the publication to cross a link whose other end is an OpenTofu apply, which
is a larger change than this one.

## Two defects found on the way

**`.bind` was not chainable.** It closed over the instance it was read off,
so `inst.bindings` inside it was always the empty set it started as: every
call folded onto `{ }` and a second `.bind` silently discarded the first.
Since `modules/lab/cluster/` binds a cluster's claim as it places the
cluster, _every_ deployer-written `.bind` on a cluster floe was being thrown
away. For a `requires` hole the ambiguity resurfaces; for an `optional` one
the hole reads null and the unit runs without it, which is the failure that
arity exists to prevent. Fixed in the floes repo with a test for the
accumulation.

The same shape was in `modules/lab/cluster/default.nix`: `withPlacement`
re-instantiated the claim to fill in `name` and `instanceName`, and
`instantiate` returns a fresh instance — so a `.bind` on a claim was dropped
there too. It carries the bindings over now.

**A lab unit may not share a name with a cluster or a claim.** All three are
units of one link joined with `//`, so a collision does not fail, it
replaces — and whatever the loser provided is simply absent. The symptom was
`attribute 'delivery' missing` from `cd.nix`, naming neither thing that
collided. A throw at the link rather than an assertion, because that
lowering runs first: `lab.steps` forces `cd.nix` long before anything reads
`lab.assertions`.
