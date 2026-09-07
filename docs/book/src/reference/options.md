# Module Options

The lab option tree is what a lab file writes: identity, DNS, networking,
host services, secrets, and the clusters.

## The shape

| Path                            | Is                                                      |
| ------------------------------- | ------------------------------------------------------- |
| `lab.name`                      | the lab's identity. Two labs on one host need two       |
| `lab.dns.*`                     | the zone, and whether the lab serves it                 |
| `lab.proxy.*`, `lab.registry.*` | host services, with their ports                         |
| `lab.network.subnet`            | the docker network. Checked against every other lab's   |
| `lab.secrets.stores.*`          | the encrypted stores, and what is projected out of them |
| `lab.provides.*`                | what the lab offers its clusters as a scope             |
| `lab.clusters.<c>`              | one cluster                                             |

And per cluster:

| Path                           | Is                                                     |
| ------------------------------ | ------------------------------------------------------ |
| `lab.clusters.<c>.floes.<n>`   | an instantiated floe                                   |
| `lab.clusters.<c>.edge.*`      | where this cluster is reached from — see RFC 0005 §6.4 |
| `lab.clusters.<c>.provisions`  | other clusters this one brings into existence          |
| `lab.clusters.<c>.secrets.*`   | project, publish and subscribe                         |
| `lab.clusters.<c>.waitTimeout` | how long a bundle may take to become ready             |

Everything else on a cluster — `provides`, `link`, `stacks`, `out`,
`manifests`, `spec` — is computed. You read those; you do not set them.

## Where a floe's own options are

**Not here.** A floe's options are its `inputs`, and they are passed as
function arguments at the instantiation site:

```nix
gateway = floes.gateway { chart = "…"; tlsEnable = true; };
```

Each floe's inputs, with types and defaults, are on its own generated page
under **Floes** in the navigation. Those pages are generated from the floe
definitions by `nix/floe-interface.nix`, and each is diff-checked by its own
flake check — so a floe whose interface changes and whose page does not is a
failing build, not a stale page.

They carry two halves. The **declaration** — inputs, requires, provides — is
read off the floe definition. What the floe **emits** — its bundles, its ops
commands, its lint checks — is read off an actual link, because an ops
command's name is not knowable until elaboration folds in the bundle it sits
on. No header could state it, and one floe documented an ops command under
the wrong name for as long as the page did not exist.

Regenerate with:

```bash
nix run .#refresh-floe-docs
```

## Not generated from `nixosOptionsDoc`

An earlier design generated per-option pages for `lab.*` and `cluster.*`
from `nixosOptionsDoc`, routed by option name. That generator is parked —
the splicer survives as `cata-build docs render` and
`cli/src/docs/options.rs`, and `pkgs/default.nix` records the gap. The table
above is hand-written and is therefore the one page in this section that can
drift; the floe pages cannot.
