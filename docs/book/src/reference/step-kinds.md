# Plan Step Kinds

Thirty-two kinds the CLI dispatches on, from `cli/src/domain/plan.rs`. A
`lab.steps.<n>.kind` must be one of these. Everything in that step's
`params` is hoisted to the top level of the emitted step, so a kind's fields
are written as `params.<field>`.

`description` is accepted by every kind and is set from the step's own
`description`. It is omitted from the tables below.

## Retry behaviour

Each kind carries an idempotency class that drives the executor's retry
policy. **This is a property of the kind, not of your declaration**: the
`idempotency` field on `lab.steps.<n>` is required as documentation of
intent, but the executor reads this table.

| Class           | Behaviour                                                                      |
| --------------- | ------------------------------------------------------------------------------ |
| **Idempotent**  | retried on failure. Probe-first, declarative, or a poll                        |
| **OneShot**     | not retried, repeating corrupts state. Use `skipIfReachable` to skip on re-run |
| **Destructive** | not retried, repeating extends the damage                                      |

## Host setup

| Kind                    | Required params             | Optional    | Class      |
| ----------------------- | --------------------------- | ----------- | ---------- |
| `setup-services`        | n/a                         | ,           | Idempotent |
| `docker-network-create` | `name`, `subnet`, `gateway` | n/a         | Idempotent |
| `colima-network-route`  | `subnet`, `profile`         | n/a         | Idempotent |
| `cert-generate`         | `zone`                      | n/a         | Idempotent |
| `host-trust-install`    | n/a                         | ,           | Idempotent |
| `dns-setup`             | `host`, `port`, `zone`      | n/a         | Idempotent |
| `registry-setup`        | `port`, `zone`              | `upstreams` | Idempotent |
| `warm-cache`            | n/a                         | ,           | Idempotent |
| `ensure-secrets`        | n/a                         | `stores`    | Idempotent |

## Clusters

| Kind                 | Required params                                               | Optional                                                            | Class       |
| -------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------- | ----------- |
| `create-cluster`     | `name`, `provisioner`                                         | `skipIfReachable`                                                   | **OneShot** |
| `sync-kubeconfig`    | `target`                                                      | `clusters`, `skipIfReachable`, `kubeContext`                        | Idempotent  |
| `wait-for-resources` | `target`                                                      | `resources`, `waitTimeoutSeconds`, `skipIfReachable`, `kubeContext` | Idempotent  |
| `pivot`              | `cluster`, `bootstrapContext`, `targetContext`, `provisioner` | `skipIfReachable`                                                   | **OneShot** |

## Manifests and delivery

| Kind                           | Required params                                   | Optional                                                         | Class       |
| ------------------------------ | ------------------------------------------------- | ---------------------------------------------------------------- | ----------- |
| `deploy-manifests`             | `target`                                          | `bootstrap`, `skipIfReachable`, `kubeContext`                    | Idempotent  |
| `pivot-bundles`                | `target`                                          | `kubeContext`, `kappApps`                                        | **OneShot** |
| `publish-manifests`            | n/a                                               | ,                                                                | Idempotent  |
| `publish-images`               | `sourceCluster`                                   | `images`                                                         | Idempotent  |
| `apply-root-application`       | `target`                                          | `namespace`, `manifestPath`, `kubeContext`                       | Idempotent  |
| `bootstrap-argocd-kubectl-ssa` | `target`, `manifestRoot`                          | `kubeContext`, `fieldManager`, `namespace`, `waitTimeoutSeconds` | Idempotent  |
| `bootstrap-argocd-helm`        | `target`, `valuesPath`, `chartRef`, `releaseName` | `kubeContext`, `namespace`, `waitTimeoutSeconds`                 | Idempotent  |
| `verify-argocd-reachable`      | `target`                                          | `kubeContext`, `namespace`                                       | Idempotent  |
| `bootstrap-forgejo-repos`      | `target`                                          | `namespace`, `jobLabelSelector`, `kubeContext`                   | Idempotent  |

The three `bootstrap-argocd-*` / `verify-argocd-reachable` kinds are
variants of one logical step selected by `lab.cd.bootstrap`. All three
publish `cluster/<n>/argocd-installed`, so anchor on the token rather than
on any one kind, or list all three with `optional:`.

## Secrets

| Kind                        | Required params                                                                                                | Optional                                       | Class      |
| --------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ---------- |
| `cross-cluster-secret-copy` | `name`, `sourceCluster`, `sourceNamespace`, `sourceSecret`, `targetCluster`, `targetNamespace`, `targetSecret` | `secretType`, `sourceContext`, `targetContext` | Idempotent |

There is no framework emitter for this, you declare it as a `lab.steps.<n>`
entry.

## Your own work

| Kind         | Required params | Optional               | Class      |
| ------------ | --------------- | ---------------------- | ---------- |
| `run-script` | `bin`           | `lifecycleName`, `env` | Idempotent |

`bin` is an absolute path to an executable, in practice
`"${pkgs.writeShellApplication { … }}/bin/<name>"`. The lab package symlinks
it into `$out/hooks/` so Nix retains it as a real runtime dependency rather
than a string-context ghost.

`env` entries are `{ name; secret; key; }`, resolved from decrypted managed
secrets before the step loop starts, so a preflight can read a cloud
credential before any cluster exists.

`lifecycleName` is what the plan renderer and failure messages display. Set
it to the step's attr key.

See [Configure a Lab](../using/configuring.md).

## Teardown

| Kind                              | Required params                  | Optional                                                                | Class           |
| --------------------------------- | -------------------------------- | ----------------------------------------------------------------------- | --------------- |
| `teardown-hooks`                  | n/a                              | `target`, `kubeContext`                                                 | Idempotent      |
| `release-cluster-cloud-resources` | `target`                         | `kubeContext`, `waitTimeoutSeconds`                                     | Idempotent      |
| `delete-managed-resource`         | `target`, `kind`, `resourceName` | `wait`, `waitTimeoutSeconds`, `kubeContext`, `externalNameDiscoveryBin` | **Destructive** |
| `wait-for-cluster-gone`           | n/a                              | `target`, `kubeContext`, `kind`, `resourceName`, `waitTimeoutSeconds`   | Idempotent      |
| `destroy-cluster`                 | `name`, `provisioner`            | `skipIfMissing`                                                         | **Destructive** |
| `remove-network`                  | n/a                              | ,                                                                       | **Destructive** |
| `remove-services`                 | n/a                              | ,                                                                       | **Destructive** |

Ordering here is not cosmetic: `release-cluster-cloud-resources` must
precede `delete-managed-resource` for the same target, or the cloud provider
orphans load balancers and volumes whose owning cluster no longer exists. A
planner assertion enforces it.

## Declaring a step

```nix
lab.steps.<name> = {
  kind        = "run-script";          # required, one of the above
  direction   = "deploy";              # deploy | teardown | both
  idempotency = "idempotent";          # required; intent, see above
  after       = [ ];                   # anchors
  before      = [ ];                   # anchors
  requires    = [ ];                   # tokens (implies `after`)
  provides    = [ ];                   # tokens
  scope       = { cluster = null; namespace = null; lab = false; };
  skipIfReachable = null;              # cluster name
  params      = { };                   # kind-specific, hoisted
  description = "";
};
```

Anchors use the plan grammar in [Anchors and Tokens](./anchors.md). Concepts
are in [How It Works](../understanding/how-it-works.md).
