# Flake Outputs

Catallaxy's public surface. Get the attribute path from here rather than
guessing, most of the wrong incantations in circulation are variations on
`mkLab` living somewhere it does not.

## System-independent

### `nixosModules.default`

The platform module tree: options, the dependency graph, the planner, the
renderers and the lint rules. It holds no floes.

`mkLab` imports it for you and supplies a floe set alongside it. Importing
it directly gets you the platform without any floes, and because
cluster-scope floes arrive through `specialArgs` rather than the import
list, you cannot add them by importing anything. It refuses rather than
evaluating to a lab that renders nothing — use `mkLab`, and pass `floes` if
you want a set other than the bundled one.

### `nixosModules.hostDns`

A NixOS module that resolves a lab's zone through the lab's DNS container,
by writing the same systemd-resolved drop-in `cata lab dns --setup` writes
with sudo. Use it on a machine NixOS manages, where a `nixos-rebuild` would
otherwise revert what the command wrote.

```nix
imports = [ catallaxy.nixosModules.hostDns ];
services.resolved.enable = true;
services.catallaxy.hostDns = {
  enable = true;
  zones."minimal.test" = { host = "127.0.0.1"; port = 5354; };
};
```

`cata lab dns` prints this filled in for the lab, next to the sudo and
dnsmasq routes. Pick one: run `cata lab dns --teardown` before switching to
the module, so the file the command wrote does not sit beside the one Nix
manages.

### `lib`

```
lib.floe.floeOptions       author a floe
lib.floe.evalFloe          isolation-test a floe
lib.floe.refs              capability and reference types
lib.mkIdempotentJob        one-shot Jobs that survive re-apply
lib.hashContent            deterministic short hash of an attrset
lib.mkNetworkPolicy        NetworkPolicy builder
lib.mkPreserveRuntimePatches   kapp rebase rules
lib.network                CIDR arithmetic
lib.evalModule             the lab evaluator
```

This is the **stable API**. `modules/` is internal: configure through
options, do not import module files. `lib/eval/` and `lib/render/` are
internal too.

See [Nix Helpers](./helpers.md) and [Floe API](./floe-api.md).

### `floeSets.default`

The floe set catallaxy ships — 29 cluster-scope floes and 2 lab-scope ones,
as `{ cluster = { <name> = <module>; ... }; lab = { ... }; }`.

`mkLab` uses it unless you pass your own. It is an attribute set rather than
a list so that you can take it apart:

```nix
mkLab {
  modules = [ ./lab.nix ];
  floes = catallaxy.floeSets.default // {
    cluster = removeAttrs catallaxy.floeSets.default.cluster [ "harbor" ] // {
      mine = ./floes/mine;
    };
  };
}
```

A floe outside the set is not an option: setting `floes.harbor.enable` under
a set without harbor is an evaluation error, not a line that is quietly
ignored.

Two caveats worth knowing before you build a set from scratch. A floe's
option _defaults_ may read another floe's `exports`, and defaults are
evaluated whether or not the producer is enabled — so a set containing
harbor must also contain gateway, cert-manager, kanidm, kaniop and
trust-manager, or it will not evaluate. And the platform still knows some
floes by name; `nix/checks/platform-floe-coupling.txt` is the current list,
held as a shrink-only baseline.

### `templates.consumer`

```bash
nix flake init -t github:onepunchtech/catallaxy#consumer
```

A working lab plus a worked floe example. See
[Build Your Own Lab](../start-here/your-own-lab.md).

## Per-system

### `legacyPackages` (where labs live)

```
legacyPackages.<system>.mkLab              evaluate a lab
legacyPackages.<system>.mkLabChecks        the checks to gate it with
legacyPackages.<system>.mkFloeChecks       the checks to gate its floes with
legacyPackages.<system>.mkLabShell         a dev shell for a lab
legacyPackages.<system>.labs.<name>        the evaluated config  (cliConfig)
legacyPackages.<system>.labPackages.<name> the rendered manifests
legacyPackages.<system>.charts             the pinned chart set
legacyPackages.<system>.k8sTypegenConfig   input for `cata generate`
```

**`labs` and `labPackages` are the two the CLI resolves.** Your consumer
flake must expose them at exactly these paths:

```nix
legacyPackages = {
  labs."my-platform" = lab.config.lab.out.cliConfig;
  labPackages."my-platform" = lab.config.lab.out.package;
};
```

They are under `legacyPackages` rather than `packages` because a lab config
is not a derivation, and `nix flake check` warns about non-derivations under
`packages`.

```nix
mkLab {
  modules = [ … ];
  floes ? floeSets.default;
} -> { config, options, ... }
```

### `mkLabChecks`

```nix
mkLabChecks {
  labs = { "<name>" = lab; … };   # labs as returned by mkLab
  snapshotLabs ? labs;            # which labs get plan snapshots
  snapshotDir ? null;             # where the committed fixtures live
} -> { "<name>-eval" = …; "<name>-lint" = …; lab-subnets = …; … }
```

Catallaxy runs this against its own example labs, so a consumer's
`nix flake check` gates on what the framework gates on. It is the whole of
`checks` in the consumer template. See
[Build Your Own Lab](../start-here/your-own-lab.md).

`snapshotDir` is opt-in because the fixtures have to live somewhere in your
repository. Without it you get everything except the plan snapshots.

### `mkFloeChecks`

```nix
mkFloeChecks {
  floes;                          # the cluster-scope set: name -> module
  mkLab;                          # builds the probe lab the export rule needs
  labs ? { };                     # labs that enable them
  sourceDir ? null;               # where the floes' source lives
  cannotKnowItsImages ? [ ];
  cannotKnowItsTraffic ? [ ];
} -> { every-floe-export-has-a-default = …; every-floe-declares-its-images = …;
       image-sets-are-complete = …; every-floe-declares-its-network = …;
       floe-boundary = …; }
```

The standards a floe set is held to, as opposed to `mkLabChecks`, which
gates a lab. Catallaxy runs it against its own set, so a consumer bringing
their own floes gets the same gates rather than having to reinvent them.

`sourceDir` is separate from `floes` because `floe-boundary` is a regex over
source text — a set of module values has no source to read. Omitting it
skips that one check rather than passing it vacuously.

`labs` matters more than it looks: image and network completeness are claims
a floe can only make good on when something enables it, so with no labs
those two gates compare against nothing.

The lab's own configuration hangs off `.config.lab.out.*`:

| Attribute                        | Is                                                                    |
| -------------------------------- | --------------------------------------------------------------------- |
| `cliConfig`                      | everything the CLI reads: clusters, plans, contexts, secrets metadata |
| `package`                        | the rendered manifest tree, hooks, lint checks, ops tool              |
| `manifests`                      | the manifest tree alone. Forcing it is the cheap eval check           |
| `deploymentPlan`, `teardownPlan` | ordered step lists, feed these to `lab plan --from-file`              |
| `allClusters`                    | per-cluster configs, including `assertions`                           |
| `runtimeContexts`                | the kube context an operator should use for each cluster right now    |

### `packages`

```
packages.<system>.default          the wrapped CLI
packages.<system>.cata             same
packages.<system>.cata-unwrapped   the bare binary, no tools on PATH
packages.<system>.option-docs      generated option markdown
packages.<system>.docs             the mdBook site
```

`cata` is wrapped in a `writeShellApplication` that puts kubectl, helm,
kapp, k3d, sops, crane and friends on PATH, so the binary never depends on
what happens to be installed.

### `apps`

```
nix run github:onepunchtech/catallaxy               # cata
nix run github:onepunchtech/catallaxy#generate-k8s-types
nix run .#<lab>-ops                                 # per lab with ops commands
```

### `devShells.default`

`cata`, `cata-dev`, every runtime tool, the Rust toolchain, and mdBook. See
[Install](../start-here/install.md).

### `checks`

`nix flake check` runs all of them.

| Group                                           | What                                                                                                                                                        |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cli`, `formatting`                             | the binary builds. Treefmt is clean                                                                                                                         |
| `docs`, `docs-options-nav`, `docs-option-links` | the book builds. Generated option pages match the nav                                                                                                       |
| `template-consumer`                             | the scaffold still evaluates against the current API                                                                                                        |
| pure-Nix fixtures                               | `plan-graph`, `manifest-graph`, `manifest-autoedges`, `k8s-helpers`, `wait-helpers`, `drift-lowering`, `mk-floe`, `floe-exports-defaults`, `contracts-oidc` |
| floe isolation                                  | `floe-<name>`, one per in-tree floe                                                                                                                         |
| out-of-tree proof                               | `floe-hello`, `floe-consumer`                                                                                                                               |
| per example lab                                 | `<lab>-lint`, `<lab>-planner-assertions`, `plan-snapshot-<lab>-{deploy,teardown}`                                                                           |

See [How It Works](../understanding/how-it-works.md).

### `formatter`

`nix fmt`, treefmt with nixfmt, rustfmt, yamlfmt.

## Common mistakes

| Wrong                                 | Right                                                |
| ------------------------------------- | ---------------------------------------------------- |
| `catallaxy.${system}.mkLab`           | `catallaxy.legacyPackages.${system}.mkLab`           |
| `catallaxy.packages.${system}.mkLab`  | same                                                 |
| `labs.<system>.<name>`                | `legacyPackages.<system>.labs.<name>`                |
| `.#labPackages.x86_64-linux."<name>"` | `.#legacyPackages.x86_64-linux.labPackages."<name>"` |
| `catallaxy.lib.clusterConfigToJSON`   | does not exist                                       |
| `lib.types`                           | does not exist. Types live in `modules/`             |
