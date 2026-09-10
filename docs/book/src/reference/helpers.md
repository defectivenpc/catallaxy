# Nix Helpers

> **This page described an API that no longer exists.** It documented a
> `k8sHelpers` module argument carrying `mkHttpRoute`, `mkTlsRoute`,
> `mkCertificate`, `mkGatewayParent` and `mkNetworkPolicy`. None of those
> names is in the tree. They are listed here so a reader with older notes
> can find where each went, rather than searching for a function that was
> deleted.

## Where they went

A floe no longer receives an ambient bag of Kubernetes helpers. Constructors
now come from `kinds`, and the ones that build a resource _against a
capability_ come from the provider through the sealed value:

| Was                          | Now                                                                     |
| ---------------------------- | ----------------------------------------------------------------------- |
| `k8sHelpers.mkHttpRoute`     | `kinds.mkRoute { inherit gateway; … }`                                  |
| `k8sHelpers.mkTlsRoute`      | `kinds.mkRoute`, with the gateway's passthrough listener                |
| `k8sHelpers.mkCertificate`   | rendered by the consumer against the sealed `X509_ISSUANCE` value       |
| `k8sHelpers.mkGatewayParent` | gone — `mkRoute` takes the sealed gateway and derives the parent itself |
| `k8sHelpers.mkNetworkPolicy` | gone. No NetworkPolicy renderer exists anywhere in the tree             |
| `catallaxy.lib.mkComponent`  | `kinds.mkComponent`                                                     |

The reason is the same in every row. A helper that takes a gateway's name
and namespace as strings requires the caller to know them; `kinds.mkRoute`
takes the _sealed_ `API_GATEWAY` value, so the caller knows only that it has
a gateway. That is what lets a floe never spell the gateway's name, its
listener, or the lab's zone.

`mkRoute` also carries the checks that used to sit elsewhere — refusing an
out-of-zone hostname at construction, rather than letting it render and be
caught by a lint over the output.

The full list of constructors is on [mkFloe API](./floe-api.md); each floe's
generated page shows which it used.

## What survives

| Helper                     | Where                         | Is                                                           |
| -------------------------- | ----------------------------- | ------------------------------------------------------------ |
| `mkIdempotentJob`          | `lib/util/idempotent-job.nix` | a one-shot Job that survives re-apply, keyed by content hash |
| `wait.*`                   | `lib/util/wait.nix`           | the readiness probe DSL                                      |
| duration, CIDR, HCL, parse | `lib/util/`                   | small pure helpers                                           |

`wait.nix` is the same probe language a bundle's `ready` uses — `kinds`
wraps it as `readyDeployment` and `readyCondition` — but rendered into a
container you place yourself. `lib/util/wait.nix:requiredBy` is the table
saying which fields a probe of each kind needs, and the elaborator checks
against it.

## Related

- [mkFloe API](./floe-api.md): `kinds.*` in full.
- [Write a Floe](../using/writing-a-floe.md): using them.
- [Bundle Schema](./bundles.md): `ready`.
