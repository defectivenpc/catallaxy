# Cluster Security

Three opt-in controls, under `lab.clusters.<c>.security`. All three are off
by default: each can refuse something that was working, and that refusal
should be somebody's decision.

## Pod Security Admission

`security.podSecurity` labels every namespace the cluster creates. It is in
the API server, so it needs no CNI support and behaves identically on k3d
and on a cloud cluster.

```nix
security.podSecurity = {
  enable = true;
  enforce = "baseline";          # what the API server refuses below
  warn = "restricted";           # what it reports without refusing
  override.podinfo = "restricted";
};
```

`warn` defaults stricter than `enforce` on purpose: the warnings are what
tell you whether raising `enforce` would break anything. `minimal.local`
runs with this on, and the first run reported that `podinfo` itself violated
`restricted` on four counts. It now sets them and is held to `restricted` by
`override` while the rest of the cluster stays at `baseline` — which is the
whole loop, and the reason `warn` is worth its noise.

`override` reads in both directions. Down for a CNI or storage driver that
genuinely needs host access, up for a workload that has earned it.

## Audit logging

`security.auditLogging` records what the API server was asked to do. k3d
only: a managed control plane logs through its provider, and a cluster the
lab did not make has no server to pass flags to.

```nix
security.auditLogging.enable = true;   # level defaults to Metadata
```

`Metadata` is who, what and when. `Request` and `RequestResponse` add the
submitted and returned objects, both of which write Secret contents to disk,
which is why neither is the default. The policy drops `get`, `list` and
`watch` before anything else — on `minimal.local` that is what takes a run
from unreadable to 1846 events, none of them reads.

## Default-deny NetworkPolicies

`security.networkPolicies.defaultDeny` takes a list of namespaces, not a
flag, and that is the honest shape rather than a smaller one.

A NetworkPolicy is additive: once any policy selects a pod, only what some
policy allows gets through. So denying a namespace means every floe
installing into it has to declare the traffic it needs — and **no floe
declares any today**. Naming one namespace at a time makes that a decision
per namespace instead of an outage. DNS to `kube-system` is excepted,
because a namespace whose pods cannot resolve turns every failure into a
name error.

It is refused outright on a cluster running k3d's default Flannel, which
implements no policy engine. The policy would apply, report healthy, and
deny nothing — which teaches that it worked. `disableFlannel = true` plus
the `cilium` floe is the combination that enforces, and `minimal.cilium`
exists to be it.

`kinds.mkNetworkPolicy` renders one; `kinds.mkDefaultDeny` renders the deny
above.

## What else exists

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

## What is still missing

Per-floe traffic declarations. Until a floe can say what it needs to reach,
`defaultDeny` on a namespace running anything real means writing the allow
rules by hand.
