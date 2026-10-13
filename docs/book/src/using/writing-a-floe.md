# Write a Floe

A floe is a **type signature with an implementation behind it**. The goal of
the shape below is that someone can read the top of the file and know what
the floe needs, what it offers, and what it installs — without reading the
body.

`floes/components/podinfo/` is the smallest complete example in the repo,
and the one this page follows.

## Is it a floe at all?

Two trees look like they could hold the same thing, so one test decides:
**could someone drop yours in its place?** `floes/` is a catalogue — every
entry is a unit of a link, named by signature, and a consumer can
`removeAttrs` one and register their own. `modules/lab/` is the shape of the
declaration they write and the lowering from it: the option tree, the
document, the plan.

So "installs Kubernetes resources" does not make something a floe, and not
installing any does not disqualify it. `floes/lab/zone.nix` installs nothing
and is a floe, because a lab could answer `DNS_ZONE` some other way.
`modules/lab/host/proxy.nix` runs a container and is not, because the lab's
own ingress is part of what a lab is rather than a choice it makes.

One exception, and it is written where it lives:
`modules/lab/cluster/security.nix` emits content — Pod Security Admission
labels and a default-deny NetworkPolicy — from the framework rather than
from a floe. They are about _every_ namespace in the cluster, including ones
other floes create, so no single floe can own them without declaring things
about its neighbours.

## The whole shape

```nix
{ lib, floe, sigs, kinds, ... }:

floe.mkFloe {
  name = "podinfo";
  summary = "podinfo, a small routed workload for proving a cluster serves traffic.";

  inputs = {
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Replica count.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  out.component = kinds.component;
  modules = [
    ({ config, lib, ... }: {
      config.floe.out.component = kinds.mkComponent { … };
    })
  ];
}
```

Seven keys, and the first six are the signature.

| Key        | Is                                                |
| ---------- | ------------------------------------------------- |
| `name`     | kebab-case, the floe's identity                   |
| `summary`  | one line saying what it installs. **Required**    |
| `inputs`   | `mkOption`s: what the deployer decides            |
| `requires` | signatures it needs. Exactly one provider each    |
| `provides` | signatures it offers back                         |
| `out`      | the kinds it emits. `component` is the common one |
| `modules`  | the body — ordinary NixOS modules                 |

`summary` is required because Nix cannot read comments. A floe's header
prose reaches no tool, so without it the generated interface page has no
title and the only machine-readable thing about a floe is its name.

There is one constructor. `requires.cluster` and `out.component` are written
out like every other line of the interface, because a floe's header is the
whole of what it promises: the two lines nearly every floe shares are the
two a reader most needs to see, and a sugar that filled them in made 38
headers quieter about what they require than about anything else.

## Requiring a capability

```nix
requires.gateway = sigs.API_GATEWAY;
```

Then in the body:

```nix
gateway = config.floe.requires.gateway;
host    = "podinfo.${gateway.baseDomain}";
```

That value is **sealed**: it holds exactly the fields `API_GATEWAY` declares
and nothing the provider happened to attach. So this floe cannot come to
depend on a traefik detail, and the gateway's author can change everything
except the signature.

Three rules follow from exactly-one-provider, and they are worth knowing
before you hit them as errors:

- **Zero providers is an error**, naming the hole and the floe. It is not a
  null you handle. If absence is genuinely tolerable, declare the hole
  `requiresOptional` and handle the null yourself.
- **Two providers is an error**, naming both. Two floes providing
  `X509_ISSUANCE` in one cluster is a question only you can answer.
- **The hole's name must be the signature's `as`.** `API_GATEWAY`'s is
  `gateway`, so the hole is `gateway`. A check enforces this across every
  floe, because `provides.operator` once bound four different signatures and
  reading it told you nothing.

Resolution is per cluster, and the lab is the outer scope. A floe requiring
`DNS_ZONE` gets its own cluster's provider if there is one and the lab's
otherwise; it says nothing about which.

## Providing a capability

```nix
provides.zone = sigs.DNS_ZONE;
```

and in the body:

```nix
config.floe.provides.zone = { zone = inputs.zone; };
```

Only the signature's fields survive. An extra key is dropped rather than
delivered, which is why a fact a consumer needs has to be _in the signature_
— adding it to the value is not enough.

## The body

`modules` is a list of ordinary NixOS modules, evaluated in the floe's own
isolated `evalModules`. `config.floe.inputs` is what the deployer passed;
`config.floe.requires.<hole>` is what the linker resolved; you write
`config.floe.out.<kind>`.

For a cluster component that is `out.component`, built with `kinds.*`:

```nix
config.floe.out.component = kinds.mkComponent {
  imagesComplete = true;

  bundles.podinfo = kinds.mkBundle {
    createNamespaces = [ inputs.namespace ];
    ready = kinds.readyDeployment { name = "podinfo"; namespace = inputs.namespace; };
    resources = {
      podinfo-deployment = { apiVersion = "apps/v1"; kind = "Deployment"; … };
      podinfo-route = kinds.mkRoute { inherit gateway; name = "podinfo"; … };
    };
  };
};
```

Notable constructors: `mkBundle`, `mkComponent`, `mkHelmChart`, `mkRoute`,
`mkGeneratedSecret`, `mkServiceAccount`, `mkOAuth2Client`, `mkOpsCommand`,
`readyDeployment`, `readyCondition`. Using a provider's constructor — as
`mkRoute` takes the sealed `gateway` — is how the shape of a resource and
the checks about it stay with the floe that serves it.

## Ordering

**Do not write cross-floe ordering. You cannot.** A bundle's `needs` names
sibling bundles in the same floe and nothing else:

```nix
bundles.issuers = kinds.mkBundle {
  needs = [ "operator" ];
  …
};
```

Everything crossing a floe boundary is derived from the link graph. If your
floe requires `X509_ISSUANCE`, the edge to whatever provided it already
exists. Some edges are derived structurally as well — a namespaced resource
after whatever declares its namespace, a custom resource after whatever
declares its CRD.

## Wrapping a chart

Most floes are a Helm chart with the values a lab needs. The chart comes
from `lib/charts.nix`, which pins it and extracts its CRDs; the floe
defaults to that pin, so a lab author never spells a version:

```nix
bundles.grafana = kinds.mkBundle {
  helmCharts.grafana = {
    chart = inputs.chart;
    namespace = ns;
    values = {
      replicas = 1;
      persistence.enabled = false;
    };
  };
};
```

`values` is the least-checked thing you will write, because a chart is a
template and not a type. Four things do check it, and it is worth knowing
which error each one gives you, because the gaps between them are where the
mistakes live.

**A quoted toggle is refused as you write it.** `enabled = "false"` is a
string, every non-empty string is true in a Go template, and the quotes
therefore turn the setting _on_. This fails evaluation naming the key.

**A value the chart has no setting for is refused by `chart-values`.** It
renders the chart with and without each value you wrote; one that changes
nothing, and that the chart's own `values.yaml` does not mention, is a value
Helm is ignoring. This is the normal outcome of a chart upgrade, and four
were live in this tree when the check was written — one of them leaving an
ApplicationSet controller running in every lab that ran Argo CD.

**A type error that breaks a template is refused by the build**, because
every build runs `helm template`. **A type error that does not** is refused
by Helm's own schema validation for the nine of twenty-one charts that ship
a `values.schema.json`, and by nothing for the rest.

**Nothing checks that the chart did what you meant.** `manifest-digests`
pins the rendered output, so a change shows up as a diff to read at review
time — but a value that is wrong in a stable way renders the same wrong
thing every time, and no digest will object. Writing a value equal to the
chart's own default is fine and not reported: it pins the behaviour against
upstream changing that default.

The escape hatch, when a chart cannot express what you need, is `yamls`.

## What the tree will make you do

Four things are checked that are easy to miss:

- **`imagesComplete`** is a claim: it says the bundle's `images` names every
  container it runs. It stays written out in every floe rather than being
  defaulted, precisely because a check believes it.
- **A Secret you reference must be created by something.** Eval walks the
  rendered resources; a Secret that arrives from a chart template, a
  controller or a plan step is invisible to that walk, so say so with
  `secrets`, `needsSecrets` or `externalSecrets`.
- **A hostname routed by an operator rather than by your own HTTPRoute** is
  equally invisible. Declare it in `routedHosts` or it is unreachable.
- **Every floe needs a test suite**, one per floe, enforced 1:1. Write it in
  `floes/tests/<name>.nix` using `floes/tests/support.nix`, which stubs each
  required signature and runs the real linker and elaborator.

## The generated page

Every floe has a reference page generated from its definition and from an
actual link — declaration on one side, what it emits on the other. They are
diff-checked, so changing a floe's interface without regenerating is a
failing build:

```bash
nix run .#refresh-docs
```

Check the result. `openbao`'s page immediately showed a header documenting
`openbao-unseal` when the real command had always been `openbao-init-unseal`
— which is the sort of thing a header can be wrong about for a year.

## Next

- [mkFloe API](../reference/floe-api.md): every argument.
- [Bundle Schema](../reference/bundles.md): every bundle field.
- [How It Works](../understanding/how-it-works.md): where the ordering comes
  from.
