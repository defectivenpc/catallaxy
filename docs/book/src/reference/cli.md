# CLI

`cata` evaluates your lab, renders manifests, and executes the plan.
Everything here is verified against `cata --help`.

## Global

```
cata [--flake <REF>] [-v|--verbose] <COMMAND>
```

| Flag              | Default | Meaning                                                      |
| ----------------- | ------- | ------------------------------------------------------------ |
| `--flake <REF>`   | `.`     | Flake to evaluate, as `<ref>#<name>`. Env: `CATALLAXY_FLAKE` |
| `-v`, `--verbose` |         | Verbose output. Valid on any subcommand                      |
| `-V`, `--version` |         | Print version                                                |

The fragment names the lab or cluster the command acts on, the same shape
`nix build .#foo` takes:

```bash
cata --flake .#<lab> lab up
cata --flake github:you/infra#prod lab plan
```

Commands that act on every lab take no fragment:

```bash
cata --flake . lab list
```

Every lab-scoped command also accepts the name positionally
(`cata --flake . lab up my-lab.local`), which is occasionally useful in a
script looping over several labs against one flake. The fragment form is
what the rest of these docs use.

The CLI resolves two flake attributes:

```
legacyPackages.<system>.labs.<lab-name>          the evaluated config
legacyPackages.<system>.labPackages.<lab-name>   the rendered manifests
```

See [Flake Outputs](./flake-outputs.md).

## Command tree

```
cata cluster     list | init | up | down | status | kubeconfig sync
cata lab         list | status | up | down | destroy | plan | plan-manifests
                 apply | lint | publish | ops | dns | topology
cata apply       [CLUSTER]
cata diagnose    [CLUSTER]
cata pki         init | issue | provision | list | kubeconfig
cata secrets     edit | encrypt | decrypt | rotate | generate | list
cata kubeconfig  show
cata images      list | mirror | prefetch
```

`cata-build` is a second binary, for maintaining the repo rather than
running a lab:

```
cata-build generate [CONFIG]
cata-build docs     render
```

## `cata lab`

Lab-level operations.

### Lifecycle

| Command              | Does                                                                 |
| -------------------- | -------------------------------------------------------------------- |
| `lab list`           | every lab this flake defines, with cluster counts                    |
| `lab status [NAME]`  | current state of clusters and host services                          |
| `lab up [NAME]`      | run the deploy plan                                                  |
| `lab down [NAME]`    | stop clusters, preserving state. Restartable with `lab up`           |
| `lab destroy [NAME]` | run the teardown plan, clusters, cloud resources, services, network  |
| `lab apply [NAME]`   | apply manifests to existing clusters, without the provisioning steps |

`lab up`:

| Flag             | Meaning                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `--dry-run`      | print what would happen without doing it                                |
| `--up-to <KIND>` | stop after the **last** step of that kind. Unknown kind is a hard error |

`--up-to` takes a step kind, not a step name:

```bash
cata --flake .#<lab> lab up --up-to=create-cluster
```

`lab down` and `lab destroy` are not synonyms. `down` stops things and keeps
state. `destroy` runs the teardown plan and deletes cloud resources.

### Inspection

| Command                     | Shows                                                    |
| --------------------------- | -------------------------------------------------------- |
| `lab plan [NAME]`           | the ordered deploy plan                                  |
| `lab plan-manifests [NAME]` | the install-wave layout for a cluster                    |
| `lab topology [NAME]`       | clusters, services, network                              |
| `lab lint [NAME]`           | environment, configuration, and rendered-manifest checks |

`lab plan`:

| Flag                 | Meaning                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `--teardown`         | the teardown plan instead of the deploy plan                                                          |
| `--stable`           | deterministic snapshot text: no colour, no emoji, no descriptions, store hashes normalized            |
| `--from-file <PATH>` | read plan JSON from a file instead of evaluating. Makes the check runnable inside a Nix build sandbox |
| `--diff <PATH>`      | diff the stable output against a baseline. Non-zero exit on mismatch. Implies `--stable`              |

`lab plan-manifests` takes `--cluster <NAME>` plus the same `--stable` /
`--from-file` / `--diff`.

`lab topology` takes `--format table|json|mermaid|dot` and `--live` (query
the cluster for real status instead of `[unknown]`).

`lab lint` takes `--path <PKG>` (lint an already-built package) and
`--skip a,b,c`. See [Lint Rules](./lint.md).

### Operations

| Command                                | Does                                        |
| -------------------------------------- | ------------------------------------------- |
| `lab ops [--name NAME] -- <ARGS>`      | run a lab-declared ops command              |
| `lab dns [NAME] [--setup\|--teardown]` | configure host DNS for the lab zone         |
| `lab publish [NAME]`                   | push rendered manifests to a git repository |

`lab ops` passes everything after `--` through, so:

```bash
cata --flake .#<lab> lab ops -- trust init-ca
cata --flake .#<lab> lab ops idm init-user lab-admin
```

`lab publish` takes `--pr`, `--message <MSG>`, `--dry-run`.

## `cata cluster`

Per-cluster operations, for when you do not want the whole lab.

| Command                             | Does                                        |
| ----------------------------------- | ------------------------------------------- |
| `cluster list`                      | clusters across all labs                    |
| `cluster init [NAME]`               | provision only: no manifests                |
| `cluster up [NAME]`                 | provision and apply                         |
| `cluster down [NAME]`               | stop and remove                             |
| `cluster status [NAME]`             | current state                               |
| `cluster kubeconfig sync [CLUSTER]` | fetch kubeconfigs for CAPI-managed clusters |

`cluster kubeconfig sync` takes `--management <M>` and `--timeout 10m`.

## `cata secrets`

| Command                      | Does                                         |
| ---------------------------- | -------------------------------------------- |
| `secrets edit <STORE>`       | decrypt, open in `$EDITOR`, re-encrypt       |
| `secrets encrypt <FILE>`     | encrypt a plaintext file (`--output <PATH>`) |
| `secrets decrypt <STORE>`    | decrypt to stdout                            |
| `secrets rotate <STORE>`     | rotate encryption keys                       |
| `secrets generate [CLUSTER]` | mint values for generator-backed keys        |
| `secrets list [CLUSTER]`     | managed secrets and their status             |

`secrets generate` takes `--secret <NAME>`, `--force`, and `--example`.
`--example` prints the plaintext YAML shape without writing anything, diff
it against your store to find keys you have not filled in yet.

See [Module Options](./options.md).

## `cata pki`

Client certificates for cluster access, optionally on a YubiKey.

| Command                 | Does                                                |
| ----------------------- | --------------------------------------------------- |
| `pki init [NAME]`       | initialize the cluster's client CA (`--force`)      |
| `pki issue <USER>`      | issue a client certificate (`--cluster`, `--force`) |
| `pki provision <USER>`  | write it to a YubiKey PIV slot (`--cluster`)        |
| `pki list [NAME]`       | CA and certificate status                           |
| `pki kubeconfig <USER>` | generate a kubeconfig entry (`--cluster`, `-o`)     |

For the _lab CA_ (the one signing service certificates) the commands are
under `lab ops -- trust`.

## `cata images`

| Command                          | Does                                                  |
| -------------------------------- | ----------------------------------------------------- |
| `images list`                    | every image the lab references                        |
| `images mirror --registry <REG>` | copy them into a registry (`--dry-run`)               |
| `images prefetch`                | pull into the local cache (`--registry`, `--dry-run`) |

All take `--name <LAB>`, or the flake fragment. See
[Images and Registries](./images.md).

## Everything else

| Command                   | Does                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------- |
| `cata apply [CLUSTER]`    | apply manifests to one cluster (`--bundle`, `--dry-run`, `--sequential`, `--force`) |
| `cata diagnose [CLUSTER]` | pods, events, deployments (`--all`, `--tail <N>`, `--since <MIN>`)                  |
| `cata kubeconfig show`    | kubeconfig contexts for lab clusters                                                |

## `cata-build`

| Command                        | Does                                                                     |
| ------------------------------ | ------------------------------------------------------------------------ |
| `cata-build generate [CONFIG]` | regenerate Kubernetes API types from OpenAPI specs and CRDs (`-o <DIR>`) |
| `cata-build docs render`       | splice generated reference pages into the book                           |

`generate` regenerates the typed schemas committed under
`lib/kubernetes/generated/`. Run it after bumping a chart whose CRDs changed
— though note that nothing in `pkgs/` builds `cata-build`, so the invocation
has to be reconstructed by hand; `docs/prior-implementations.md` records
this as a known gap.

## Removed commands

If you have older notes:

| Was                                       | Now                                   |
| ----------------------------------------- | ------------------------------------- |
| `cata lab init`                           | `cata lab up --up-to=create-cluster`  |
| `cata lab trust --setup`                  | `cata lab ops -- trust setup`         |
| `cata lab trust --teardown`               | `cata lab ops -- trust teardown`      |
| `cata lab trust --export`                 | `cata lab ops -- trust export`        |
| `cata kubeconfig sync`                    | `cata cluster kubeconfig sync`        |
| `cata lab up --phase/--component/--force` | removed. They were parsed and ignored |
