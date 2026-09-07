# Configure a Lab

Your lab lives in your own repository and takes catallaxy as a flake input.

## The two attribute paths

The CLI resolves exactly two attributes:

```nix
legacyPackages.<system> = {
  labs."my-platform"        = lab.config.lab.out.cliConfig;   # nix eval reads this
  labPackages."my-platform" = lab.config.lab.out.package;     # nix build reads this
};
```

`cata --flake .#my-platform` finds them by name. Nothing else in your flake
matters to it. See [Flake Outputs](../reference/flake-outputs.md).

## A lab

`mkLab` takes a list of modules and returns an evaluation:

```nix
lab = catallaxy.legacyPackages.${system}.mkLab {
  modules = [ ./lab.nix ./envs/local.nix ];
};
```

The lab file comes first and the environment files after, so the lab uses
`lib.mkDefault` for anything an environment overrides.
`examples/labs/minimal/` is the smallest complete worked example in this
repo, and it and its five environments are built by CI, so they cannot rot.

## Instantiating floes

A floe is a function. Calling it produces an opaque value, and a cluster is
an attrset of those:

```nix
lab.clusters.app.floes = {
  cluster      = floes.k3d-cluster  { name = "app"; instanceName = "minimal-app"; };
  cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
  gateway      = floes.gateway      { chart = "${cataCharts.traefik.chart}"; };
  podinfo      = floes.podinfo      { };
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

A floe that needs the lab's DNS zone requires `DNS_ZONE`; the lab offers it
as a **scope**, and every cluster resolves against the union of its own
floes and the lab's offers, nearer-first. A cluster running its own zone
provider shadows the lab's, and neither the floe nor your lab file says
which.

Portability is per field. A field marked local does not cross a cluster
boundary, so a value that only makes sense inside one cluster cannot quietly
be read from another. RFC 0005 §3.1 and §3.2 are the reference.

Reading a value across clusters gives you the right _address_ for something
elsewhere — it does not move data. Moving an actual Secret between clusters
goes through the lab's secret stores: one cluster publishes into a store and
another subscribes from it.

## Layering across environments

Lab configuration is ordinary module configuration, so put the shape in the
lab file and the differences in an env file:

```nix
# lab.nix
lab.dns.zone = lib.mkDefault "minimal.test";

# envs/tls.nix
lab.name            = "minimal.tls";
lab.proxy.httpsPort = 8443;
```

Adding a floe in an environment is a merge. _Replacing_ one the lab file
already declared needs `lib.mkForce`, because a floe instance is an opaque
value and the module system has no merge for two of them:

```nix
gateway = lib.mkForce (floes.gateway {
  chart     = "${cataCharts.traefik.chart}";
  tlsEnable = true;
});
```

Environments need distinct identities to run side by side — their own
`lab.name`, subnet and host ports. A lab-level check refuses two labs that
claim one host port or overlapping docker subnets.

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
