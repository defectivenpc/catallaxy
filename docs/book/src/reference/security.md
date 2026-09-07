# Cluster Security

> **The `cluster.security.*` options this page described are not built.** It
> documented three opt-in controls — Pod Security Admission labelling,
> default-deny NetworkPolicies, and API server audit logging — under
> `cluster.security.podSecurity`, `.networkPolicies` and `.auditLogging`.
> None of those option paths exists, and neither does `mkNetworkPolicy`.
> They are named here because "the option is missing" is more useful to a
> reader than a page that quietly omits the subject.

There is no NetworkPolicy renderer anywhere in the tree. A `network` channel
on a component carried a `declared` flag that 31 of 31 floes set to `true`
and that nothing ever read; it was deleted rather than defaulted, because a
claim nobody acts on is worse than no claim.

## What does exist

| Concern                            | Where                                                       |
| ---------------------------------- | ----------------------------------------------------------- |
| Client certificates, incl. YubiKey | `cata pki`, [CLI](./cli.md)                                 |
| Encrypted secrets at rest          | `lab.secrets.stores.*`, `cata secrets`                      |
| Moving a secret between clusters   | publish/subscribe through a lab store — never a copy in Nix |
| Secrets a manifest must not carry  | a check refuses secret material in rendered output          |
| TLS and CA trust                   | the `cert-manager` and `trust-manager` floes                |
| Single sign-on                     | the `kanidm` floe and `OIDC_PROVIDER`                       |
| What is reachable from outside     | the `gateway` floe, and `lab.clusters.<c>.edge`             |
| Image provenance and mirroring     | [Images and Registries](./images.md)                        |

Two of those are worth stating as guarantees rather than as options, because
they hold without anyone turning them on:

**A generated secret is generated in the cluster.** A floe that needs a
credential declares it and a generator mints it there; the value does not
pass through Nix, so it cannot reach the store or a rendered manifest. An
eval-time check asks, of every Secret referenced, which floe creates it —
and refuses one that nothing does.

**A route may not leave its zone.** `kinds.mkRoute` refuses an out-of-zone
hostname at construction, so a workload cannot claim a name the lab does not
serve.

## If you want the missing controls

Pod Security Admission is namespace labels, so a floe can emit them today
with no framework support at all. Default-deny NetworkPolicies would need a
renderer that does not exist and a CNI that enforces them — Cilium does,
k3d's default Flannel does not, which is why a policy applied on a local lab
would be inert and would teach the wrong lesson about whether it worked.
