# Build Your Own Lab

Your lab lives in your own flake with catallaxy as an input. You never fork
it.

## Scaffold

```bash
mkdir my-platform && cd my-platform
nix flake init -t github:onepunchtech/catallaxy#consumer
```

Five files:

```
flake.nix                          catallaxy input, mkLab, outputs
lab.nix                            your topology
floes/default.nix                  your floe registry
floes/hello-world/default.nix      a worked example floe
floes/hello-world/options.nix      its option surface
```

## The flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    catallaxy.url = "github:onepunchtech/catallaxy";
  };

  outputs = { nixpkgs, flake-utils, catallaxy, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        lib = nixpkgs.lib;

        myFloes = import ./floes {
          inherit lib;
          inherit (catallaxy.lib.floe) mkFloe;
        };

        lab = catallaxy.legacyPackages.${system}.mkLab {
          modules = [ (import ./lab.nix { inherit myFloes; }) ];
        };
      in {
        legacyPackages = {
          labs."my-platform" = lab.config.lab.out.cliConfig;
          labPackages."my-platform" = lab.config.lab.out.package;
        };
      });
}
```

Two attribute paths are load-bearing, because they are what the CLI looks
for:

```
legacyPackages.<system>.labs.<lab-name>          the evaluated config
legacyPackages.<system>.labPackages.<lab-name>   the rendered manifests
```

`mkLab` is under `legacyPackages` (not `packages`) because a lab is not a
derivation and `nix flake check` would complain. The full surface is in
[Flake Outputs](../reference/flake-outputs.md).

A floe is a function, not a module to import, so your own floes reach the
lab as an ordinary argument. See [Write a Floe](../using/writing-a-floe.md).

## The lab

```nix
{ myFloes }:
{ lib, cataCharts, floes, ... }:
{
  lab.name = "my-platform";
  lab.dns.zone = "example.test";

  lab.clusters.app.floes = {
    cluster = floes.k3d-cluster {
      name = "app";
      instanceName = "my-platform-app";
    };

    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    gateway      = floes.gateway      { chart = "${cataCharts.traefik.chart}"; };

    hello-world = myFloes.hello-world { replicas = 2; };
  };
}
```

Notice what is **not** there. Nothing says `hello-world` comes after
`gateway`, and nothing passes the gateway's address or the lab's zone into
it. Your floe declares `requires.gateway = sigs.API_GATEWAY`; the linker
resolves it against this cluster, checks that exactly one floe provides it,
and derives the ordering edge. See [The Model](../understanding/model.md).

## Run it

```bash
nix develop github:onepunchtech/catallaxy

cata --flake .#my-platform lab plan
cata --flake .#my-platform lab lint
cata --flake .#my-platform lab up
```

`--flake .` alone works too, if the lab name matches, but being explicit is
clearer with more than one lab.

## Grow it

The template is one file because one cluster in one environment is one
file's worth of decisions. Past that, split by _what a file answers_: the
convention both example labs use:

```
labs/default.nix       what the platform IS       topology, ops commands
clusters/core.nix      what THIS cluster is       which capabilities run here
aspects/identity.nix   what ONE capability is     kanidm + everything it wires to
envs/prod.nix          WHERE it runs              provisioners, domains, credentials
```

A lab is then a base plus an environment:

```nix
allLabs = {
  "my-platform.local" = mkLab [ ./labs/default.nix ./envs/local.nix ];
  "my-platform.prod"  = mkLab [ ./labs/default.nix ./envs/prod.nix ];
};
```

None of this is framework machinery. There is no `aspect` type. It is a
directory convention that falls out of the module system. Copy the shape
from
[`examples/labs/homelab`](https://github.com/onepunchtech/catallaxy/tree/master/examples/labs/homelab).

## Add checks early

The scaffold ships one:

```nix
checks.lab-eval =
  let forced = builtins.toJSON lab.config.lab.out.manifests;
  in pkgs.runCommand "lab-eval" { } ''
    cat > /dev/null <<'JSON'
    ${forced}
    JSON
    echo "my-platform evaluated" > $out
  '';
```

Forcing the manifest tree touches every option, so an unmet `requires`, a
bad `exports` read, or a broken anchor fails in CI rather than at `lab up`.
Add [plan snapshots](../understanding/how-it-works.md) next, they turn any
change in deploy ordering into a reviewable diff.

## Next

- [Configure a Lab](../using/configuring.md): the floes you can turn on,
  options, overrides, and per-environment layering.
- [Write a Floe](../using/writing-a-floe.md): when `floes.custom` stops
  being enough.
- [Module Options](../reference/options.md): every option, generated.
