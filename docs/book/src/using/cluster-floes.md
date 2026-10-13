# Reuse a Cluster

A floe is one capability. A floe's units may be other floes, which is how
the cluster you keep building gets made once and used from anywhere.

## Using one

```nix
app = mkClusterFloe {
  name = "app";
  requires.claim = sigs.KUBERNETES_CLUSTER;

  units = _: {
    platform = floes.standard-cluster { };

    myapp = floes.myapp { };
  };
};
```

That is a whole cluster: the Gateway API CRDs, an issuer, trust
distribution, in-cluster DNS, a gateway and a secret generator — plus your
app, and a hole for the thing that brings the cluster into existence.

Three things about that block are decisions rather than accidents.

**The claim sits beside it, not inside it.** `standard-cluster` installs
into a cluster and does not make one, so it leaves `requires.claim` open and
whoever places it answers. That is what lets one assembly serve a k3d
cluster on a laptop, a Talos cluster, and one that already exists — the lab
writes the claim under the cluster:

```nix
clusters = _: {
  app = {
    floe = clusters.app { };
    claim = floes.talos-cluster { };
  };
};
```

**Your app goes beside it too.** `myapp` requiring `API_GATEWAY` resolves
against what the assembly exports, exactly as if you had written the gateway
yourself. There is nothing to wire.

**What crosses out of it is declared.** An inclusion exports nothing by
default, so a signature an app resolves against has to be named in
`exports`. That is what makes this an interface rather than an arrangement
of files, and it is why the first ten lines of the definition tell you what
the assembly offers.

## Changing one

By its inputs, like any floe.

```nix
platform = floes.standard-cluster {
  tls = false;
  rootFromLab = true;
};
```

There is no `omit` and no `overrides`. Leaving a member out or swapping one
was what a preset needed because it had no interface of its own to
parameterise; an inclusion has `inputs`, and a member that should be
optional is a member whose input says so.

If you find yourself wanting to omit most of it, you want your own assembly
rather than this one bent out of shape.

## Writing one

```nix
catallaxy.floe.mkFloe {
  name = "standard-cluster";
  summary = "CRDs, an issuer, trust, DNS, a gateway and a generator.";

  inputs.tls = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether the gateway terminates TLS.";
  };

  # Left open: nothing in here makes a cluster or knows the lab's zone.
  requires = {
    cluster = sigs.KUBERNETES_CLUSTER;
    zone = sigs.DNS_ZONE;
  };

  provides.gateway = sigs.API_GATEWAY;
  exports.gateway = "gateway/gateway";

  units =
    { inputs, ... }:
    {
      gateway-api = floes.gateway-api-crds { };
      cert-manager = floes.cert-manager { };
      gateway = floes.gateway { tlsEnable = inputs.tls; };
    };
}
```

`requires` is the part worth getting right. **Every hole nothing inside
answers has to be declared**, and a hole nothing inside _reads_ is refused —
so the list cannot drift in either direction without the link saying so.

`exports` names which inner provide each `provides` is. The export signature
is usually narrower than the one inside, and the narrowing is what keeps a
field meaningful only in there from leaving; `link` refuses an export that
promises more than what it re-exports.

Assemblies live in `floes/clusters/`, beside the components in
`floes/components/`. Both are floes and a lab reaches both through `floes`;
the directories are layout, not a namespace.

## What nesting changes

The units inside keep their own names, qualified by the assembly holding
them. A bundle from the gateway lands at `platform/gateway/gateway` rather
than `gateway/gateway`, and that shows up in manifest paths, in
`cata lab plan-manifests`, and in the digests.

Two instances of one assembly are two sets of units, so a lab with two
clusters each holding a `platform` gets a `platform/cert-manager` in each,
keyed by the cluster it is in.

## When not to

An assembly is for something that means something **outside the lab that
first wrote it**. Repetition inside one lab is what a local function is for,
and reaching for an interface there buys nothing and costs one.

`examples/labs/tests/secret-sharing.nix` is the worked counter-example. Two
clusters share three floes — a provisioner, a generator and a store pointed
at one backend — and it stays a local function. `standard-cluster` does not
fit it: five of its six members would be unwanted, and an assembly you use a
sixth of is one you are fighting.

## Next

- [`standard-cluster`](../reference/floes/standard-cluster.md): the shipped
  one, generated from its definition.
- [Write a Floe](./writing-a-floe.md): when a member does not exist yet.
- [The Model](../understanding/model.md): where inclusion comes from.
