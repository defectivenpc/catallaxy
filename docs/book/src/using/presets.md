# Reuse a Cluster

A floe is one capability. A **preset** is an assembly of them with an
interface — the cluster you keep building, made once and used from anywhere.

## Using one

```nix
lab.clusters.app.floes = {
  platform = presets.standard-cluster {
    provisioner = floes.k3d-cluster { };
  };

  myapp = floes.myapp { };
};
```

That is a whole cluster: the Gateway API CRDs, an issuer, trust
distribution, in-cluster DNS, a gateway and a secret generator — plus your
app.

Your app goes **beside** the preset, not into it. Expansion is flat, so
`myapp` requiring `API_GATEWAY` resolves against the preset's gateway
exactly as if you had written both yourself. There is nothing to wire.

The **provisioner is required and has no default**. Every provisioner
answers `KUBERNETES_CLUSTER`, so the same preset serves a laptop, a Talos
cluster and one that already exists:

```nix
provisioner = floes.talos-cluster { };
```

A preset that shipped a default would quietly make every cluster k3d, which
is the failure that only shows up in production.

## Changing one

Two inputs, both checked against the members.

```nix
platform = presets.standard-cluster {
  provisioner = floes.k3d-cluster { };

  omit = [ "lab-dns" ];
  overrides.gateway = floes.gateway { tlsEnable = false; };
};
```

Naming something the preset does not have is refused, with the member list
in the message — a typo that silently omitted nothing is how a preset
becomes something people fork instead of parameterise.

Omitting a member the preset needs to keep its promises is refused too:

```
preset 'standard-cluster': says it provides API_GATEWAY, which no member does.
```

If you find yourself omitting most of it, you want your own preset rather
than this one bent out of shape.

## Writing one

```nix
catallaxy.mkPreset {
  name = "standard-cluster";
  summary = "A cluster with CRDs, an issuer, trust, DNS, a gateway and a generator.";

  inputs = {
    provisioner = lib.mkOption { type = lib.types.raw; description = "…"; };
    tls = lib.mkOption { type = lib.types.bool; default = true; description = "…"; };
  };

  provides = {
    gateway = sigs.API_GATEWAY;
    issuance = sigs.X509_ISSUANCE;
  };

  members = inputs: {
    cluster = inputs.provisioner;
    gateway = floes.gateway { tlsEnable = inputs.tls; };
    cert-manager = floes.cert-manager { };
  };
}
```

`provides` is the part that makes this more than a function. It is **checked
against the members**, so it is a claim rather than a comment — the shipped
preset's list was wrong when it was first written, and instantiating it said
so before any lab used it.

Declared need not be exhaustive: a member may provide more than the preset
advertises. Requiring the full list would make adding a member a breaking
change.

Presets live in `floes/presets/` and are applied after the floe set, because
their members come from it. A lab reaches them as `presets.<name>`.

## When not to

A preset is for an assembly that means something **outside the lab that
first wrote it**. Repetition inside one lab is what a local function is for,
and reaching for a preset there buys nothing and costs an interface.

`examples/labs/tests/secret-sharing.nix` is the worked counter-example. Two
clusters share three floes — a provisioner, a generator and a store pointed
at one backend — and it stays a closure. `standard-cluster` does not fit it:
five of seven members would have to be omitted, and the preset then refuses
itself, because a declaration it can no longer keep is exactly what `omit`
is checked against.

    preset 'standard-cluster': says it provides API_GATEWAY, GATEWAY_API,
    X509_ISSUANCE, TRUST_BUNDLE, which no member does.

That refusal is the design working. If you find yourself omitting most of a
preset, you do not want that preset — you want a local function, or a
different preset that someone else will also use.

## Two things to know

**Members keep their own names.** `gateway` is `gateway`, not
`platform-gateway`. That is what lets `lab.clusters.<c>.provides` name a
member as `<instName>/<provide>`, and what lets an app resolve against one.

The cost is collision. A member and something you write directly under the
same name is refused, naming both:

```
cluster 'app': 'gateway' comes from preset 'platform' and is also written
directly in this cluster. Replace it with `overrides.gateway`, or `omit` it.
```

Last-wins would have been quieter and would have made a preset impossible to
trust.

**A preset is not a floe instance.** It is expanded into its members before
anything links, so the linker only ever sees ordinary floes — which is why a
preset can hold a provisioner and a workload at once, something no single
floe can do.

## Next

- [`standard-cluster`](../reference/floes/standard-cluster.md): the shipped
  one, generated from its definition.
- [Write a Floe](./writing-a-floe.md): when a member does not exist yet.
- [The Model](../understanding/model.md): where inclusion comes from.
