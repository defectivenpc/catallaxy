# Build Your Own Lab

Your lab lives in your own flake with catallaxy as an input. You never fork
it.

## Scaffold

```bash
mkdir my-platform && cd my-platform
nix flake init -t github:defectivenpc/catallaxy#consumer
```

Four files:

```
flake.nix                          catallaxy input, mkLab, outputs
lab.nix                            your topology
floes/default.nix                  your floe registry
floes/hello-world/default.nix      a worked example floe
```

## The flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    catallaxy.url = "github:defectivenpc/catallaxy";
  };

  outputs = { nixpkgs, flake-utils, catallaxy, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        cata = catallaxy.legacyPackages.${system};

        myFloes = cata.mkFloes (import ./floes);

        lab = cata.mkLab (
          (import ./lab.nix {
            inherit myFloes;
            inherit (cata) catallaxy floes;
            inherit (nixpkgs) lib;
          })
          { name = "my-platform"; }
        );
      in {
        legacyPackages = {
          labs."my-platform" = lab.cliConfig;
          labPackages."my-platform" = lab.package;
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
{ lib, floes, catallaxy, myFloes }:

catallaxy.mkLabFloe {
  name = "my-platform";
  summary = "One cluster, and the floes you wrote in it.";

  inputs.zone.default = "example.test";

  clusters = _: {
    app = {
      floe =
        catallaxy.mkClusterFloe {
          name = "app";
          summary = "A platform behind a gateway, and your app.";
          requires.claim = catallaxy.sigs.KUBERNETES_CLUSTER;
          provides.delivery = catallaxy.sigs.DELIVERY_POLICY;
          exports.delivery = "kapp/delivery";

          units = _: {
            kapp = floes.kapp { };
            gateway-api = floes.gateway-api-crds { };
            cert-manager = floes.cert-manager { };
            gateway = floes.gateway { };

            hello = myFloes.hello-world { replicas = 2; };
          };
        }
        { };

      claim = floes.k3d-cluster { };
    };
  };
}
```

Notice what is **not** there. No chart paths — each floe defaults its own
from the pin, and you override only to run a fork. No cluster name or
container name — the attribute path already said `app`, and the lab's name
tells two `app` clusters apart. No subnet and no host ports: those are
derived from the lab's name and recorded in an allocation table, so two
people adding labs on separate branches do not collide at merge.

And nothing says `hello-world` comes after `gateway`, and nothing passes the
gateway's address or the lab's zone into it. Your floe declares
`requires.gateway = sigs.API_GATEWAY`; the linker resolves it against this
cluster, checks that exactly one floe provides it, and derives the ordering
edge. See [The Model](../understanding/model.md).

## Run it

```bash
nix develop github:defectivenpc/catallaxy

cata --flake .#my-platform lab plan
cata --flake .#my-platform lab lint
cata --flake .#my-platform lab up
```

`--flake .` alone works too, if the lab name matches, but being explicit is
clearer with more than one lab.

### Reaching the cluster

A lab's clusters go in the **lab's own kubeconfig**, not `~/.kube/config`:

```bash
eval "$(cata --flake .#my-platform lab env)"
kubectl config get-contexts
```

That is why a fresh `kubectl config get-contexts` shows nothing after
`lab up` — nothing is wrong, and nothing was written over. A lab cannot
clobber a cluster you actually depend on, and `cata lab cleanup` can delete
the whole file without taking your other contexts with it.

`lab env` sets `KUBECONFIG` and, if the lab has a CA, the variables that
trust it. `--shell fish`, `--shell json` and `--unset` are there too. The
file itself is at `~/.local/share/catallaxy/labs/<lab>/kube/config` if you
would rather point something at it directly.

Tear it down with `cata --flake .#my-platform lab down`. That one does not
prompt, so it takes no `--yes`; `cata lab cleanup <name> --yes` is the one
that does, because it removes state a rebuild cannot recover.

### Against a checkout

To try a change to catallaxy itself — or a version that is not published yet
— point the input at a working copy:

```bash
nix flake lock --override-input catallaxy /path/to/catallaxy
```

Everything above then resolves against that tree. This is the loop for
developing a floe and the lab that uses it at the same time, and it is worth
knowing before you need it: without it the scaffold silently gets the last
published catallaxy, which is the wrong one to be debugging against.

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
[`examples/labs/homelab`](https://github.com/defectivenpc/catallaxy/tree/master/examples/labs/homelab).

## Add checks early

The scaffold ships one:

```nix
checks.lab-renders = lab.package;
```

Rendering the lab touches every option, so an unmet `requires`, a bad
`exports` read, or a broken anchor fails in CI rather than at `lab up`. Add
[plan snapshots](../understanding/how-it-works.md) next, they turn any
change in deploy ordering into a reviewable diff.

## Next

- [Configure a Lab](../using/configuring.md): the floes you can turn on,
  options, overrides, and per-environment layering.
- [Write a Floe](../using/writing-a-floe.md): when `floes.custom` stops
  being enough.
- [Module Options](../reference/options.md): every option, generated.
