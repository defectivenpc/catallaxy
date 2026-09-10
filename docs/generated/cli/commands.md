# CLI Commands

Every command and flag, generated from the parser. The judgement, the flake fragment and what replaced the removed commands are in [CLI](../cli.md).

## Global flags

| Flag | Default | Meaning |
| --- | --- | --- |
| `--flake <REF>` | `.` | Flake to evaluate, as &lt;ref&gt;#&lt;name&gt; |
| `-v, --verbose` |  | Verbose output |

| Command | Does |
| --- | --- |
| [`cata cluster list`](#cluster-list) | List clusters across all labs |
| [`cata cluster init`](#cluster-init) | Provision the cluster only, applying no manifests |
| [`cata cluster up`](#cluster-up) | Provision the cluster and apply its manifests |
| [`cata cluster down`](#cluster-down) | Stop and remove the cluster |
| [`cata cluster status`](#cluster-status) | Show the cluster's current state |
| [`cata lab cleanup`](#lab-cleanup) | Remove what a lab left on this machine. Needs no flake |
| [`cata lab list`](#lab-list) | Labs this flake defines, and labs running on this machine |
| [`cata lab status`](#lab-status) | Show the current state of clusters and host services |
| [`cata lab up`](#lab-up) | Run the deploy plan |
| [`cata lab down`](#lab-down) | Stop clusters, preserving state. Restartable with 'lab up' |
| [`cata lab destroy`](#lab-destroy) | Run the teardown plan: clusters, cloud resources, services, network |
| [`cata lab plan`](#lab-plan) | Show the ordered deploy plan |
| [`cata lab plan-manifests`](#lab-plan-manifests) | Show the install-wave layout for a cluster |
| [`cata lab diff`](#lab-diff) | Show what applying would change in the running clusters |
| [`cata lab apply`](#lab-apply) | Apply manifests to existing clusters, without the provisioning steps |
| [`cata lab verify`](#lab-verify) | Check a running lab against what it declares |
| [`cata lab lint`](#lab-lint) | Run environment, configuration and rendered-manifest checks |
| [`cata lab publish`](#lab-publish) | Push rendered manifests to a git repository |
| [`cata lab ops`](#lab-ops) | Run a lab-declared ops command. Arguments after '--' are passed through |
| [`cata lab dns`](#lab-dns) | Configure host DNS for the lab zone |
| [`cata lab topology`](#lab-topology) | Show clusters, services and network |
| [`cata lab env`](#lab-env) | Print shell exports that trust the lab CA in the current shell |
| [`cata apply`](#apply) | Apply manifests to one cluster |
| [`cata diagnose`](#diagnose) | Show pods, events and deployments for a cluster |
| [`cata pki init`](#pki-init) | Initialize the cluster's client CA |
| [`cata pki issue`](#pki-issue) | Issue a client certificate for a user |
| [`cata pki provision`](#pki-provision) | Write a user's certificate to a YubiKey PIV slot |
| [`cata pki list`](#pki-list) | Show CA and certificate status |
| [`cata pki kubeconfig`](#pki-kubeconfig) | Generate a kubeconfig entry for a user's certificate |
| [`cata secrets edit`](#secrets-edit) | Decrypt a store, open it in $EDITOR, and re-encrypt on save |
| [`cata secrets encrypt`](#secrets-encrypt) | Encrypt a plaintext file |
| [`cata secrets decrypt`](#secrets-decrypt) | Decrypt a store to stdout |
| [`cata secrets rotate`](#secrets-rotate) | Re-encrypt a store to the current set of recipients |
| [`cata secrets generate`](#secrets-generate) | Mint values for generator-backed keys |
| [`cata secrets init-intermediate`](#secrets-init-intermediate) | Mint an intermediate CA signed by the lab's root CA |
| [`cata secrets list`](#secrets-list) | List managed secrets and their status |
| [`cata kubeconfig show`](#kubeconfig-show) | Show the kubeconfig contexts for the lab's clusters |
| [`cata images list`](#images-list) | List every image the lab references |
| [`cata images actual`](#images-actual) | List every image the lab's clusters are actually running |
| [`cata images mirror`](#images-mirror) | Copy the lab's images into a registry |
| [`cata images lock`](#images-lock) | Resolve every image the lab references to a digest and write a lockfile |
| [`cata images prefetch`](#images-prefetch) | Pull the lab's images into the local registry cache |

## `cata cluster`

Per-cluster operations, for when you do not want the whole lab

### `cata cluster list` {#cluster-list}

List clusters across all labs

```
cata cluster list
```

### `cata cluster init` {#cluster-init}

Provision the cluster only, applying no manifests

```
cata cluster init [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

### `cata cluster up` {#cluster-up}

Provision the cluster and apply its manifests

```
cata cluster up [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--bundle <BUNDLE>` |  | Apply only this bundle |
| `--dry-run` |  | Print what would happen without doing it |
| `--force` |  | Apply directly even when the cluster's deploy strategy is GitOps |

### `cata cluster down` {#cluster-down}

Stop and remove the cluster

```
cata cluster down [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

### `cata cluster status` {#cluster-status}

Show the cluster's current state

```
cata cluster status [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

## `cata lab`

Lab-level operations

### `cata lab cleanup` {#lab-cleanup}

Remove what a lab left on this machine. Needs no flake

```
cata lab cleanup [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to remove, as it appears in `lab list` |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--all` |  | Every lab found on this machine |
| `--orphans` |  | Only leftovers no lab claims |
| `--dry-run` |  | Print what would be removed and stop |
| `--yes` |  | Do not ask before removing |
| `--keep-state` |  | Leave the lab's state directory, including its CA |

### `cata lab list` {#lab-list}

Labs this flake defines, and labs running on this machine

```
cata lab list [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--json` |  | Print as JSON |

### `cata lab status` {#lab-status}

Show the current state of clusters and host services

```
cata lab status [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--json` |  | Emit the state as JSON instead of a table |

### `cata lab up` {#lab-up}

Run the deploy plan

```
cata lab up [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--dry-run` |  | Print what would happen without doing it |
| `--up-to <KIND>` |  | Stop after the last step of this kind |
| `--recreate <CLUSTER>` |  | Destroy and rebuild this cluster if its shape no longer matches the lab. Repeat for several, or pass '*' for all. Everything on it is lost |
| `--infra` |  | Run steps that create or destroy real infrastructure. Without it they are skipped and named |

### `cata lab down` {#lab-down}

Stop clusters, preserving state. Restartable with 'lab up'

```
cata lab down [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

### `cata lab destroy` {#lab-destroy}

Run the teardown plan: clusters, cloud resources, services, network

```
cata lab destroy [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--dry-run` |  | Print what would be destroyed without destroying it |
| `--up-to <KIND>` |  | Stop after the last step of this kind |
| `--infra` |  | Run steps that create or destroy real infrastructure. Without it they are skipped and named |

### `cata lab plan` {#lab-plan}

Show the ordered deploy plan

```
cata lab plan [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--teardown` |  | Show the teardown plan instead of the deploy plan |
| `--stable` |  | Deterministic snapshot text: no colour, no emoji, no descriptions, store hashes normalized |
| `--from-file <PATH>` |  | Read plan JSON from a file instead of evaluating |
| `--diff <PATH>` |  | Diff the stable output against a baseline, exiting non-zero on mismatch. Implies --stable |

### `cata lab plan-manifests` {#lab-plan-manifests}

Show the install-wave layout for a cluster

```
cata lab plan-manifests [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--cluster <NAME>` |  | Cluster to lay out |
| `--stable` |  | Deterministic snapshot text: no colour, no emoji, no descriptions, store hashes normalized |
| `--from-file <PATH>` |  | Read plan JSON from a file instead of evaluating |
| `--diff <PATH>` |  | Diff the stable output against a baseline, exiting non-zero on mismatch. Implies --stable |

### `cata lab diff` {#lab-diff}

Show what applying would change in the running clusters

```
cata lab diff [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--bundle <BUNDLE>` |  | Diff only this bundle |
| `--cluster <CLUSTER>` |  | Diff only this cluster |

### `cata lab apply` {#lab-apply}

Apply manifests to existing clusters, without the provisioning steps

```
cata lab apply [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--bundle <BUNDLE>` |  | Apply only this bundle |
| `--cluster <CLUSTER>` |  | Apply only to this cluster |
| `--dry-run` |  | Print what would happen without doing it |
| `--force` |  | Apply directly even when the cluster's deploy strategy is GitOps |

### `cata lab verify` {#lab-verify}

Check a running lab against what it declares

```
cata lab verify [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--check <CHECK>` |  | Run only this check |
| `--json` |  | Emit diagnostics as JSON instead of a report |

### `cata lab lint` {#lab-lint}

Run environment, configuration and rendered-manifest checks

```
cata lab lint [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--path <PATH>` |  | Lint an already-built package instead of evaluating |
| `--skip <RULES>` |  | Comma-separated rule names to skip |

### `cata lab publish` {#lab-publish}

Push rendered manifests to a git repository

```
cata lab publish [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--pr` |  | Open a pull request instead of pushing to the branch |
| `--message <MSG>` |  | Commit message |
| `--dry-run` |  | Print what would be published without pushing |

### `cata lab ops` {#lab-ops}

Run a lab-declared ops command. Arguments after '--' are passed through

```
cata lab ops [OPTIONS] [ARGS]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `ARGS` | no | Ops command and its arguments |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <NAME>` |  | Lab to act on. Defaults to the flake fragment |

### `cata lab dns` {#lab-dns}

Configure host DNS for the lab zone

```
cata lab dns [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--setup` |  | Install the resolver configuration |
| `--teardown` |  | Remove the resolver configuration |

### `cata lab topology` {#lab-topology}

Show clusters, services and network

```
cata lab topology [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `-f, --format <FORMAT>` | `table` | Output format |
| `--live` |  | Query the clusters for real status instead of [unknown] |

### `cata lab env` {#lab-env}

Print shell exports that trust the lab CA in the current shell

```
cata lab env [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--shell <SHELL>` | `posix` | Output syntax for the exports |
| `--unset` |  | Print statements that clear the exports instead |

## `cata apply`

Apply manifests to one cluster

### `cata apply` {#apply}

Apply manifests to one cluster

```
cata apply [OPTIONS] [CLUSTER]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `CLUSTER` | no | Cluster to apply to. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--bundle <BUNDLE>` |  | Apply only this bundle |
| `--dry-run` |  | Print what would happen without doing it |
| `--force` |  | Apply directly even when the cluster's deploy strategy is GitOps |

## `cata diagnose`

Show pods, events and deployments for a cluster

### `cata diagnose` {#diagnose}

Show pods, events and deployments for a cluster

```
cata diagnose [OPTIONS] [CLUSTER]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `CLUSTER` | no | Cluster to inspect. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--all` |  | Inspect every cluster in the lab |
| `--tail <N>` | `20` | Log lines to show per unhealthy pod |
| `--since <MINUTES>` | `30` | How far back to look for warning events |

## `cata pki`

Client certificates for cluster access, optionally on a YubiKey

### `cata pki init` {#pki-init}

Initialize the cluster's client CA

```
cata pki init [OPTIONS] [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--force` |  | Replace an existing CA |

### `cata pki issue` {#pki-issue}

Issue a client certificate for a user

```
cata pki issue [OPTIONS] <USER>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `USER` | yes | User to act on, declared in the cluster's apiserver.pki.users |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--cluster <NAME>` |  | Cluster to act on. Defaults to the flake fragment |
| `--force` |  | Reissue even if a certificate already exists |

### `cata pki provision` {#pki-provision}

Write a user's certificate to a YubiKey PIV slot

```
cata pki provision [OPTIONS] <USER>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `USER` | yes | User to act on, declared in the cluster's apiserver.pki.users |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--cluster <NAME>` |  | Cluster to act on. Defaults to the flake fragment |

### `cata pki list` {#pki-list}

Show CA and certificate status

```
cata pki list [NAME]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | no | Cluster to act on. Defaults to the flake fragment |

### `cata pki kubeconfig` {#pki-kubeconfig}

Generate a kubeconfig entry for a user's certificate

```
cata pki kubeconfig [OPTIONS] <USER>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `USER` | yes | User to act on, declared in the cluster's apiserver.pki.users |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--cluster <NAME>` |  | Cluster to act on. Defaults to the flake fragment |
| `-o, --output <PATH>` |  | Where to write the kubeconfig. Defaults to stdout |

## `cata secrets`

Manage the encrypted secret stores

### `cata secrets edit` {#secrets-edit}

Decrypt a store, open it in $EDITOR, and re-encrypt on save

```
cata secrets edit <STORE>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `STORE` | yes | Store name from lab.secrets.stores, or a path to an encrypted file |

### `cata secrets encrypt` {#secrets-encrypt}

Encrypt a plaintext file

```
cata secrets encrypt [OPTIONS] <FILE>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `FILE` | yes | Plaintext file to encrypt |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--output <PATH>` |  | Where to write the ciphertext. Defaults to &lt;FILE&gt;.enc.yaml |

### `cata secrets decrypt` {#secrets-decrypt}

Decrypt a store to stdout

```
cata secrets decrypt <STORE>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `STORE` | yes | Store name from lab.secrets.stores, or a path to an encrypted file |

### `cata secrets rotate` {#secrets-rotate}

Re-encrypt a store to the current set of recipients

```
cata secrets rotate <STORE>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `STORE` | yes | Store name from lab.secrets.stores, or a path to an encrypted file |

### `cata secrets generate` {#secrets-generate}

Mint values for generator-backed keys

```
cata secrets generate [OPTIONS] [LAB]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `LAB` | no | Lab to act on. Defaults to the flake fragment |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--secret <NAME>` |  | Generate only this secret |
| `--force` |  | Regenerate stores that already exist |
| `--example` |  | Print the plaintext shape without writing anything |
| `--format <FORMAT>` | `sops` | sops encrypts the store files; env prints the VAR=value lines an env-backed store reads, and writes nothing |

### `cata secrets init-intermediate` {#secrets-init-intermediate}

Mint an intermediate CA signed by the lab's root CA

```
cata secrets init-intermediate [OPTIONS] <NAME>
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `NAME` | yes | Managed secret to hold the intermediate. Must be declared with kind = "ca" |

| Flag | Default | Meaning |
| --- | --- | --- |
| `--root <NAME>` |  | Root CA to sign with. Defaults to the only other kind = "ca" secret in the store |
| `--days <DAYS>` | `365` | Validity in days |
| `--force` |  | Replace an intermediate that is already in the store, reissuing every leaf under it |

### `cata secrets list` {#secrets-list}

List managed secrets and their status

```
cata secrets list [LAB]
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `LAB` | no | Lab to act on. Defaults to the flake fragment |

## `cata kubeconfig`

Inspect kubeconfig contexts for lab clusters

### `cata kubeconfig show` {#kubeconfig-show}

Show the kubeconfig contexts for the lab's clusters

```
cata kubeconfig show
```

## `cata images`

Inspect and mirror the container images a lab references

### `cata images list` {#images-list}

List every image the lab references

```
cata images list [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <LAB>` |  | Lab to act on. Defaults to the flake fragment |

### `cata images actual` {#images-actual}

List every image the lab's clusters are actually running

```
cata images actual [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <LAB>` |  | Lab to act on. Defaults to the flake fragment |
| `--cluster <CLUSTER>` |  | Only this cluster. Defaults to every cluster in the lab |
| `--undeclared` |  | Only the images the lab never rendered, which is what an operator created |

### `cata images mirror` {#images-mirror}

Copy the lab's images into a registry

```
cata images mirror [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <LAB>` |  | Lab to act on. Defaults to the flake fragment |
| `--registry <REGISTRY>` |  | Registry to copy images into |
| `--dry-run` |  | Print what would be copied without copying it |

### `cata images lock` {#images-lock}

Resolve every image the lab references to a digest and write a lockfile

```
cata images lock [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <LAB>` |  | Lab to act on. Defaults to the flake fragment |
| `--out <PATH>` | `images.lock.json` | Lockfile to write, relative to the flake |

### `cata images prefetch` {#images-prefetch}

Pull the lab's images into the local registry cache

```
cata images prefetch [OPTIONS]
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--name <LAB>` |  | Lab to act on. Defaults to the flake fragment |
| `--registry <REGISTRY>` | `localhost:5050` | Registry cache to pull into |
| `--dry-run` |  | Print what would be pulled without pulling it |

