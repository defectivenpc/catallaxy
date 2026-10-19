# Configure a Lab

Your lab lives in your own repository and takes catallaxy as a flake input.

## The two attribute paths

The CLI resolves exactly two attributes:

```nix
legacyPackages.<system> = {
  labs."my-platform"        = lab.cliConfig;   # nix eval reads this
  labPackages."my-platform" = lab.package;     # nix build reads this
};
```

`cata --flake .#my-platform` finds them by name. Nothing else in your flake
matters to it.

## A lab

A lab is a floe. `lab.nix` is the definition and `mkLab` lowers one
instantiation of it:

```nix
lab = catallaxy.legacyPackages.${system}.mkLab (
  (import ./lab.nix { inherit lib; inherit (cata) catallaxy floes; })
    { name = "my-platform"; }
);
```

`examples/labs/minimal/` is the smallest complete worked example in this
repo, and it and its five environments are built by CI, so they cannot rot.

## Instantiating floes

A floe is a function. Calling it produces an opaque value, and a cluster
floe's units are an attrset of those:

```nix
app = mkClusterFloe {
  name = "app";
  requires.claim = sigs.KUBERNETES_CLUSTER;

  units = _: {
    cert-manager = floes.cert-manager { };
    gateway      = floes.gateway { };
    podinfo      = floes.podinfo { };
  };
};
```

The arguments are the floe's **inputs** — what the deployer decides. Each
floe's inputs, with types and defaults, are on its own generated reference
page.

There is no `enable`. A floe absent from the attrset is not instantiated; if
something required what it provided, that is a link error naming both.

## Threading in your own floes

`floes` reaches your modules as an argument, so your own floes go in the
same attrset alongside the shipped ones. There is no auto-discovery: a floe
directory nothing imports does nothing at all — no error, no manifests.

## Wiring floes together

**You do not wire floes together.** That is the point of the design, and it
is the largest single difference from configuring a chart-based platform.

A floe names the _capability_ it needs, and the linker finds whatever
provides it in that cluster:

```nix
requires.gateway = sigs.API_GATEWAY;    # inside the floe, not in your lab
```

So nothing in your lab file connects `podinfo` to `gateway`. You put both in
the cluster; the link is derived, checked, and ordered. Adding a second
gateway to that cluster is an error naming both — not a silent
last-one-wins.

What you _do_ configure is what a signature cannot decide for you: the chart
to use, the replica count, the domain. Those are inputs.

### Values from the lab, and from another cluster

A floe that needs the lab's DNS zone requires `DNS_ZONE`; the lab exposes it
as a **scope**, and every cluster resolves against the union of its own
floes and the lab's offers, nearer-first. A cluster running its own zone
provider shadows the lab's, and neither the floe nor your lab file says
which.

Portability is per field. A field marked local does not cross a cluster
boundary, so a value that only makes sense inside one cluster cannot quietly
be read from another.

Reading a value across clusters gives you the right _address_ for something
elsewhere — it does not move data. Moving an actual Secret between clusters
goes through the lab's secret stores: one cluster publishes into a store and
another subscribes from it.

## Layering across environments

An environment is an instantiation. The lab declares the inputs its
environments may vary, with defaults, and each `envs/*.nix` answers them:

```nix
# lab.nix
inputs = {
  zone.default = "minimal.test";

  cluster = lib.mkOption {
    type = catallaxy.floeInstance;
    default = clusters.app { };
  };
};

# envs/tls.nix
lab {
  name = "minimal.tls";
  cluster = clusters.app { tls = true; };
  units.proxy = floes.lab-proxy { httpsPort = 8443; };
}
```

So what can differ between two environments is readable from the
definition's header, and there is no merge to reason about: adding a floe is
a key in `units`, and withdrawing one the lab placed is `units.<n> = null`.
It was `lib.mkDefault` on every base value and `lib.mkForce` to replace one,
because a floe instance is opaque and the module system had no merge for two
of them.

Environments need distinct identities to run side by side, and they get them
from their own `name`: the subnet and every host port are derived from it,
and each lab's document carries what it was given. Set one by hand only when
the address is somebody's contract — a firewall rule, a bookmark — and a
lab-level check still refuses two labs that collide.

## The escape hatch

Something to run that has no floe of its own and does not need one:

```nix
hello = floes.custom {
  name = "hello";
  # resources, an optional chart, and a route in front
};
```

One app per instance, not an attrset of them — a `provides` answers one hole
once, so a floe holding N apps could not attach N routes through a rule that
resolves exactly one.

## Checking it

```bash
cata --flake .#minimal.local lab lint
cata --flake .#minimal.local lab plan
cata --flake .#minimal.local lab up
```

`lab up` is idempotent; running it against a healthy lab is a no-op plus a
re-apply, which is the right response to "something got changed by hand".

Most of what can go wrong is refused before any of those run.
`nix flake check` forces the manifest tree, so an unsatisfied `requires`, a
second provider, a route outside the zone, or a reference to a Secret
nothing creates fails there rather than part-way through a deploy.

## Next

- [Write a Floe](./writing-a-floe.md)
- [CLI](../reference/cli.md): every command.
- [Module Options](../reference/options.md): the lab option tree.
