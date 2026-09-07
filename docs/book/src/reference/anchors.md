# Anchors and Tokens

Catallaxy has two dependency graphs. They share this grammar and nothing
else:

|             | Nodes                       | Where you author edges                           | Explained in                                     |
| ----------- | --------------------------- | ------------------------------------------------ | ------------------------------------------------ |
| Install DAG | bundles, within one cluster | `bundles.<b>.{after,requires,provides}`          | [How It Works](../understanding/how-it-works.md) |
| Plan DAG    | steps, across the whole lab | `lab.steps.<n>.{after,before,requires,provides}` | [How It Works](../understanding/how-it-works.md) |

## Anchor grammar

An _anchor_ is a string naming other nodes. It resolves to a set, and every
member of that set becomes a predecessor.

### Install DAG (`lib/eval/manifest-graph.nix`)

| Form               | Matches                                          |
| ------------------ | ------------------------------------------------ |
| `<name>`           | the bundle with that exact key                   |
| `bundle:<name>`    | the same, written explicitly                     |
| `floe:<floe-name>` | bundles emitted by that floe                     |
| `provides:<token>` | every bundle whose `provides` contains the token |
| `optional:<expr>`  | any of the above, but a miss is silent           |

A bundle's key is its name, so the anchor is `bundle:cert-manager`.

> `floe:<name>` works: it matches every bundle whose `declaredBy` is that
> floe, which `lib/kubernetes/types.nix` stamps at construction.
>
> `kind:` is **deliberately absent** from the resolver. It used to mean "any
> bundle holding a resource of this kind", which reads the same as "the
> thing that admits one" and answers the opposite question — every emitter
> of a Certificate, rather than the one floe that installs its CRD. A
> `kind:` anchor now falls through to the ordinary provided-name index, so
> the floe installing the CRD supplies it by name.

### Plan DAG (`lib/eval/plan-graph.nix`)

| Form                    | Matches                                          |
| ----------------------- | ------------------------------------------------ |
| `<name>`                | the step with that attr key                      |
| `kind:<kind>`           | every step of that kind                          |
| `kind:<kind>:<cluster>` | steps of that kind whose `scope.cluster` matches |
| `provides:<token>`      | every step whose `provides` contains the token   |
| `optional:<expr>`       | any of the above, but a miss is silent           |

## The fail-loud contract

These throw at eval rather than surfacing at apply time:

**A hard anchor that matches nothing.**

```
bundle 'forgejo': needs names 'operators/cnpg', which nothing on
this cluster provides.

A name resolves against a bundle of that name, then against
everything any bundle lists in `provides`. Derived names carry a
prefix (bundle:, floe:, kind:, namespace:); hand-written ones are
bare, by convention <scope>/<subject>/<state>. `step:<token>`
reaches a lab plan step instead, for something that has to happen
before the manifests are applied at all.

Supply it with `provides = [ "operators/cnpg" ]` on the bundle that does,
or write it as 'optional:operators/cnpg' if it is allowed to match
nothing.
```

`kind:` and `namespace:` appear in that list as **derived** names —
`lib/eval/manifest-autoedges.nix` stamps them onto the bundle that installs
a CRD or declares a namespace. They are resolved through the ordinary
provided-name index, which is why they are not forms in the table above.

**A `requires` token nobody provides.**

```
bundle 'apps/forgejo': requires 'reloader/watching' but no bundle provides it.
Declare a bundle with `provides = [ "reloader/watching" ]` or drop the require.
```

In practice this usually means a floe was enabled without its dependency.
`mkFloe`'s own `requires` catches the common cases earlier, with a message
naming both floes.

**A cycle**, reported with the strongly-connected set:

```
manifest bundles: dependency cycle among: ["a","b"].
At least one pair of bundles mutually require each other via
after/requires edges. Inspect the anchor lists on the named
bundles and break the cycle.
```

A bundle that both provides and requires the same token is _not_ a cycle,
self-edges are filtered.

## Structural auto-edges

Three edges are derived from Kubernetes shape rather than authored
(`lib/eval/manifest-autoedges.nix`). They are inserted as **hard**
`bundle:<provider>` anchors, because a consumer referencing a namespace, CRD
kind, or SecretStore that no bundle declares is a real bug.

| Consumer                                                                                                                 | Provider                                                                                        | Why                                                             |
| ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| any resource with `metadata.namespace`, any helm release with a `namespace`, any bundle listing it in `createNamespaces` | the bundle declaring that `Namespace`, or the synthetic `namespaces/_all` aggregate             | the apply blocks or fails until the namespace exists            |
| any resource whose `kind` matches a declared CRD's `spec.names.kind`                                                     | the bundle providing the CRD                                                                    | applying a CR before its CRD races the apiserver's schema cache |
| an `ExternalSecret`                                                                                                      | the bundle declaring the `SecretStore` / `ClusterSecretStore` in its `spec.secretStoreRef.name` | ESO won't reconcile until the store is Ready                    |

Self-references are filtered: a bundle that declares a Namespace _and_ puts
workloads in it gets no self-edge.

## Synthesized tokens

| Token                | Emitted by                                                                                                                                         |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `stage1`             | every bundle in the DAG closure of `cluster.provisioning.rootBundles`                                                                              |
| `secret:<ns>/<name>` | the virtual `projection/<name>` bundle for each `secrets.projections.<name>`. Consumers referencing that Secret get a matching `requires` injected |

## Built-in bundle tokens

Published by the in-tree floes. Convention: `<scope>/<subject>/<state>`.

```
argocd/server/ready                         gateway-api/crds/established
cert-manager/crds/established               gateway/controller/ready
cert-manager/default-issuer/ready           gateway/public/ready
cert-manager/webhook/ready                  gateway/tls/ready
cilium/cni/ready                            grafana/ui/ready
cluster-api/operator/ready                  harbor/registry/ready
cluster-api/providers/ready                 kanidm/instance/ready
cnpg/operator/ready                         kanidm/provisioning/ready
coredns/lab-dns/ready                       kaniop/crds/established
crossplane/crds/established                 kaniop/operator/ready
crossplane/managed-resources/reconciling    loki/read/ready
crossplane/operator/ready                   openebs/storage/ready
crossplane/provider-configs/ready           otel-collector/gateway/ready
crossplane/providers/installed              prometheus/crds/established
external-dns/reconciler/ready               prometheus/scrape/ready
external-secrets/crds/established           redis-operator/ready
external-secrets/webhook/ready              reloader/watching
forgejo/git/ready                           seaweedfs/s3/ready
netbird/{api-key,management,operator,…}     tempo/write/ready
trust-manager/bundles/ready                 velero/backup/ready
velero/crds/established                     zot/registry/ready
```

## Built-in plan tokens

Published by framework-emitted steps (`modules/lab/plan.nix` and
`modules/lab/planner/`).

**Deploy:**

```
lab/preflight-ok        lab/network             lab/host-network
lab/ingress-ca          host/trust              host/dns
lab/registry-config     lab/secrets             lab/services
lab/warm-cache          lab/manifests-pushed

cluster/<n>/created                cluster/<n>/bootstrap-deployed
cluster/<n>/provisioner-done       cluster/<n>/kubeconfig-synced
cluster/<n>/pivoted                cluster/<n>/argocd-installed
cluster/<n>/forgejo-bootstrapped   cluster/<n>/gitops-started
```

**Teardown adds:**

```
cluster/<n>/teardown-hooks-done    cluster/<n>/cloud-released
cluster/<n>/mr-deleted             cluster/<n>/gone
cluster/<n>/destroyed              lab/services-removed
```

## Built-in plan step names

Anchor on these by name when a token isn't specific enough. `<n>` is a
cluster name.

```
docker-network-create   colima-network-route   cert-generate
host-trust-install      dns-setup              registry-setup
ensure-secrets          setup-services         warm-cache
create-cluster-<n>      apply-root-<n>         bootstrap-forgejo-<n>
publish-manifests       publish-images-<n>     preflight-<n>-<hook>

teardown-hooks-<n>      release-<n>-cloud      delete-mr-<n>
wait-cluster-gone-<n>   destroy-cluster-<n>    destroy-cluster-bootstrap-<n>
remove-services         remove-network
```

Prefer `optional:` on all of these. Which steps a plan contains depends on
the environment: a local k3d lab has no pivot, a cloud lab has four extra
steps, and a hard anchor on a step that env never emits fails eval by
design.
