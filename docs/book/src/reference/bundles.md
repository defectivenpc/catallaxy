# Bundle Schema

A bundle is a group of Kubernetes resources installed as a unit, and the
node type of the install DAG. Written to `bundles.<name>`. Declared in
`lib/kubernetes/types.nix`.

A bundle's key is its name, unique within the cluster.

## Fields

| Field                | Type                         | Default | Meaning                                                                                           |
| -------------------- | ---------------------------- | ------- | ------------------------------------------------------------------------------------------------- |
| `resources`          | `attrsOf kubernetesResource` | `{}`    | Typed Kubernetes resources, kind-dispatched against generated schemas                             |
| `yamls`              | `listOf (str or path)`       | `[]`    | Raw YAML escape hatch, inline or by path                                                          |
| `helmCharts`         | `attrsOf helmChart`          | `{}`    | Chart releases. See below                                                                         |
| `createNamespaces`   | `listOf str`                 | `[]`    | Namespaces to create. Unioned cluster-wide and rendered by the synthetic `namespaces/_all` bundle |
| `includeInBootstrap` | `bool`                       | `true`  | When `false`, excluded from the stage1 (pre-pivot) manifest set                                   |
| `after`              | `listOf str`                 | `[]`    | Ordering-only anchors, "install after this", with no readiness requirement                        |
| `requires`           | `listOf str`                 | `[]`    | Tokens that must be **ready** (applied _and_ ready probe passed)                                  |
| `provides`           | `listOf str`                 | `[]`    | Tokens this bundle emits once ready                                                               |
| `readyProbe`         | `nullOr attrs`               | `null`  | How to decide the bundle is ready. See below                                                      |
| `owner.bootstrap`    | `nullOr enum`                | `null`  | `"install-target"` or `"argocd"`. `null` inherits `lab.cd.defaultOwner.bootstrap`                 |
| `owner.steady`       | `nullOr enum`                | `null`  | `"imperative"` or `"argocd"`. `null` inherits `lab.cd.defaultOwner.steady`                        |

`after` versus `requires`: `after` is pure sequencing. B lands in a later
wave than A. `requires` additionally blocks on A's ready probe. Reach for
`requires` whenever the dependency is on state A _creates_ (a CRD becoming
Established, a Certificate being issued) rather than merely on A's manifests
existing.

The anchor grammar for `after` is in [Anchors and Tokens](./anchors.md).

## `helmCharts.<release>`

| Field                       | Type                   | Default                |
| --------------------------- | ---------------------- | ---------------------- |
| `chart`                     | `package`              | required               |
| `releaseName`               | `str`                  | the attr name          |
| `namespace`                 | `str`                  | `"default"`            |
| `values`                    | `attrs`                | `{}`                   |
| `createNamespace`           | `bool`                 | `true`                 |
| `extraOpts`                 | `listOf str`           | `[ "--skip-tests" ]`   |
| `kustomize.enable`          | `bool`                 | `false`                |
| `kustomize.patches`         | `listOf attrs`         | `[]` (strategic merge) |
| `kustomize.patchesJson6902` | `listOf attrs`         | `[]`                   |
| `kustomize.resources`       | `listOf (path or str)` | `[]`                   |

Resources carrying a `helm.sh/hook` annotation are stripped during render.
See [How It Works](../understanding/how-it-works.md) for why, and what to do
instead.

## `readyProbe`

A kind-tagged attrset from the probe DSL in `lib/util/wait.nix`. When
`null`, the bundle counts as ready as soon as its resources apply.

Use `null` for purely declarative bundles (Secret, ConfigMap, Namespace).
Use a probe for bundles that _mint state_: a Certificate, a CRD, an OAuth2
client, an external database, so a downstream `requires` blocks until the
state is real rather than until the manifest landed.

```nix
readyProbe = {
  kind = "condition";
  resource = "certificate/lab-ca";
  namespace = "cert-manager";
  condition = "Ready";
  timeout = "3m";
};
```

| `kind`         | Waits for                        | Runs           |
| -------------- | -------------------------------- | -------------- |
| `condition`    | a status condition on a resource | host-side      |
| `jsonpath`     | a JSONPath expression to match   | host-side      |
| `exists`       | a resource to exist at all       | host-side      |
| `script`       | an arbitrary script to exit 0    | host-side      |
| `kubectl-wait` | free-form `kubectl wait` args    | host-side      |
| `http`         | an HTTP endpoint to answer       | in-cluster Pod |
| `tcp`          | a TCP port to accept             | in-cluster Pod |
| `dns`          | a name to resolve                | in-cluster Pod |

Host-side probes run against the operator's kubeconfig. The three network
shapes address endpoints the host generally cannot reach, so the renderer
turns them into a one-shot Pod. That Pod carries no ServiceAccount and
therefore cannot mount the lab CA bundle: if a probe needs the lab CA, put a
`mkWaitInitContainer` inside the bundle's own workload (where the volume
already exists) and give the bundle a kubectl-native `readyProbe` instead.

## Example

```nix
bundles.redis-operator = {
  includeInBootstrap = false;

  helmCharts.redis-operator = {
    chart = cfg.chart;
    releaseName = "redis-operator";
    namespace = cfg.namespace;
    createNamespace = true;
  };
  createNamespaces = [ cfg.namespace ];

  provides = [ "redis-operator/ready" ];
  readyProbe = {
    kind = "condition";
    resource = "deployment/redis-operator";
    namespace = cfg.namespace;
    condition = "Available";
    timeout = "3m";
  };
};
```

Nothing here states _when_ to install it. Downstream bundles that need a
Redis instance declare `requires = [ "redis-operator/ready" ]`, and the wave
partition follows.
