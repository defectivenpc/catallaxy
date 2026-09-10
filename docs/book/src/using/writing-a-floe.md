# Write a Floe

A floe is a **type signature with an implementation behind it**. The goal of
the shape below is that someone can read the top of the file and know what
the floe needs, what it offers, and what it installs — without reading the
body.

`floes/cluster/podinfo/` is the smallest complete example in the repo, and
the one this page follows.

## The whole shape

```nix
{ lib, catallaxy, sigs, kinds, ... }:

catallaxy.mkComponentFloe {
  name = "podinfo";
  summary = "podinfo, a small routed workload for proving a cluster serves traffic.";

  inputs = {
    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Replica count.";
    };
  };

  requires.gateway = sigs.API_GATEWAY;

  modules = [
    ({ config, lib, ... }: {
      config.floe.out.component = kinds.mkComponent { … };
    })
  ];
}
```

Six keys, and the first five are the signature.

| Key        | Is                                             |
| ---------- | ---------------------------------------------- |
| `name`     | kebab-case, the floe's identity                |
| `summary`  | one line saying what it installs. **Required** |
| `inputs`   | `mkOption`s: what the deployer decides         |
| `requires` | signatures it needs. Exactly one provider each |
| `provides` | signatures it offers back                      |
| `modules`  | the body — ordinary NixOS modules              |

`summary` is required because Nix cannot read comments. A floe's header
prose reaches no tool, so without it the generated interface page has no
title and the only machine-readable thing about a floe is its name.

`mkComponentFloe` is sugar over `mkFloe` that defaults two constants:
`requires.cluster = sigs.KUBERNETES_CLUSTER` and `out.component`. Both are
plumbing — every floe that installs into a cluster wrote the same two lines
— and a check verifies the wiring exists rather than believing the author.
Use `floe.mkFloe` directly for anything that is not a cluster component.

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
nix run .#refresh-floe-docs
```

Check the result. `openbao`'s page immediately showed a header documenting
`openbao-unseal` when the real command had always been `openbao-init-unseal`
— which is the sort of thing a header can be wrong about for a year.

## Next

- [mkFloe API](../reference/floe-api.md): every argument.
- [Bundle Schema](../reference/bundles.md): every bundle field.
- [How It Works](../understanding/how-it-works.md): where the ordering comes
  from.
