# Flake Outputs

Catallaxy's public surface. Get the attribute path from here rather than
guessing, most of the wrong incantations in circulation are variations on
`mkLab` living somewhere it does not.

## System-independent

### `nixosModules.default`

The whole module tree. `mkLab` uses it for you. You would only import it
directly to build a lab without `mkLab`.

### `lib`

```
lib.floe.mkFloe            author a floe
lib.floe.evalFloe          isolation-test a floe
lib.floe.oidc              OIDC scope-contract assertions
lib.mkIdempotentJob        one-shot Jobs that survive re-apply
lib.hashContent            deterministic short hash of an attrset
lib.mkNetworkPolicy        NetworkPolicy builder
lib.mkPreserveRuntimePatches   kapp rebase rules
lib.network                CIDR arithmetic
lib.evalModule             the lab evaluator
lib.mkComponent            the pre-floe primitive (legacy)
```

This is the **stable API**. `modules/` is internal: configure through
options, do not import module files. `lib/eval/` and `lib/render/` are
internal too.

See [Nix Helpers](./helpers.md) and [mkFloe API](./floe-api.md).

### `templates.consumer`

```bash
nix flake init -t github:onepunchtech/catallaxy#consumer
```

A working lab plus a worked `mkFloe` example. See
[Build Your Own Lab](../start-here/your-own-lab.md).

## Per-system

### `legacyPackages` (where labs live)

```
legacyPackages.<system>.mkLab              evaluate a lab
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
mkLab { modules = [ … ]; } -> { config, options, ... }
```

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

| Group                                    | What                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------- |
| `cli`, `cli-clippy`                      | the binary builds and is clippy-clean, and its own test suites run    |
| `formatting`                             | treefmt is clean                                                      |
| `docs`, `rfc-refs`                       | the book builds with no dead link; every RFC `§N` citation resolves   |
| `floe-<name>`                            | one test suite per floe, enforced 1:1                                 |
| `floe-interface-<name>`                  | the generated page matches the floe. One per floe                     |
| `floe-core`, `floe-cluster`              | the linker and the elaborator                                         |
| `floe-headers`, `floe-names`             | no prose naming a removed primitive; one canonical name per signature |
| `plan-{deploy,teardown}-<lab>`           | committed plan snapshots                                              |
| `manifest-digest-<lab>`                  | committed digests of the rendered tree                                |
| `cliConfig-<lab>`                        | committed `cliConfig` for each lab                                    |
| `<lab>-lint`, `<lab>-eval`               | the lint rules, and that the manifest tree forces                     |
| `<lab>-renders-no-secret-material`       | no secret value reaches a rendered manifest                           |
| `images-complete-<lab>-<cluster>-<floe>` | every container is named in the floe's image set                      |
| `lab-*`                                  | cross-lab facts: subnets, host ports, edges, routed hosts             |
| `util-*`, `secret-*`, `render-infra`     | pure-Nix fixtures over `lib/`                                         |

The per-lab and per-floe families expand with the tree, so the total moves;
`nix flake check` prints it.

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
