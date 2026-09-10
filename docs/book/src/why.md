# Why Catallaxy

Kubernetes platform engineering has an accidental complexity problem: YAML
sprawl across environments, deployment ordering that lives in tribal
knowledge, brittle bash glue that breaks silently, and a bootstrap
chicken-and-egg that someone has to solve by hand every time.

Catallaxy treats your platform like a compilation problem. Declare
components in typed Nix modules. Cross-cluster references resolve through
lazy evaluation at build time. Deployment ordering is a dependency graph,
not a runbook. The same declarations compile to kapp, ArgoCD, or Fleet
output without changing component code.

## The problems we keep solving by hand

### YAML sprawl

Every Kubernetes environment accumulates YAML. Helm values files for dev,
staging, prod. Kustomize overlays stacked on top of overlays. Patches for
patches. Across a multi-cluster platform, you end up with thousands of lines
of templated configuration, most of it duplicated with minor variations.
When something needs to change, you grep across directories and hope you
found every copy.

### Tribal knowledge

How do you deploy this platform from scratch? Which namespace needs to exist
before the operator can start? What order do the Helm releases go in? Where
does the CA certificate come from, and which components need it injected?
The answers live in someone's head, a runbook that's three versions behind,
or a Slack thread from last year. Every new team member re-discovers this
the hard way.

### Brittle procedural scripting

The gap between "here are my Helm charts" and "here is a running platform"
gets filled with scripts. Bash that shells out to kubectl, helm, and jq in
careful sequence. Python wrappers that parse YAML to generate more YAML. CI
pipelines stitched together with retry loops, sleep statements, and
post-deploy health checks that paper over ordering bugs. These scripts work
until they don't, and when they break, they break silently or in ways that
are hard to diagnose.

### The bootstrap problem

Your child clusters get GitOps, declarative config, drift detection, and
automated reconciliation. But the management cluster that runs all of that?
It was click-ops'd into existence on AWS. Someone followed a wiki page,
clicked through a console, ran some Terraform, and manually applied a
handful of Helm charts until ArgoCD was alive enough to take over.

The management plane is always manual. Always imperative. Always a special
case that doesn't get the same rigor as everything it manages. And when you
need to rebuild it (disaster recovery, region migration, new environment),
you discover how much institutional knowledge was baked into that original
bootstrap sequence that nobody wrote down completely.

### No type safety

Helm values are untyped YAML. A misspelled key is silently ignored. A wrong
type produces valid YAML that fails at apply time, or worse, applies
successfully and breaks at runtime. You find out when the on-call gets
paged, not when the configuration was written. There is no compile step, no
editor completion, no structural guarantee that what you wrote matches what
the chart expects.

### Non-reproducible builds

The same Helm chart, the same values file, can produce different output
depending on the Helm binary version, which OCI registry responded, whether
a transitive dependency was cached, or what the network looked like at build
time. "It worked yesterday" is not an explanation, but it is often all you
have. Diffing what actually changed between two deploys requires forensic
effort.

## How Catallaxy addresses this

Catallaxy replaces ad-hoc tooling with a compiler-like approach: declare
what you want, and the system resolves it into exactly the manifests each
cluster needs.

### Nix as the foundation

The NixOS module system provides typed options with defaults, lazy
evaluation for cross-references, and deterministic builds. Your entire
platform (every component, every cluster, every environment variation) is a
single Nix expression that evaluates to a set of Kubernetes manifests.
Cross-cluster references (like pointing one cluster's OTEL collector at
another cluster's Tempo endpoint) resolve at build time through lazy
evaluation. No runtime service discovery. No ordering scripts. No glue.

### Self-contained components

Each infrastructure component is a self-contained Nix module. It declares
its own options, its own defaults, the manifests it emits, and the
conditions it needs. Want to understand what the cert-manager component
does? Read it. Nothing about it is configured somewhere else. There is no
configuration scattered across directories, no implicit dependencies between
files, and no hidden wiring, which is what makes it possible to evaluate one
component in isolation and reason about it completely.

### Dependency-based ordering

CRDs before operators. Operators before infrastructure. Infrastructure
before apps. None of that is written as a sequence of steps in a script, or
as a number someone chose. Each part declares what it needs and what it
offers, and the build system resolves the graph. The bootstrap problem
(which resources must exist before others can be created) becomes a
build-time property, and "ready" means a declared readiness condition
actually passed, not that a manifest was accepted.

### Type-checked configuration

Kubernetes resources are typed from OpenAPI specs and CRD schemas. Helm
values are structured Nix attrsets, not free-form YAML. Structural errors
surface at `nix eval` time, before anything is rendered or applied. Your
editor can provide completion. Your CI can catch misconfigurations. You find
problems when you write the code, not when you deploy it.

### Reproducible by construction

Manifests are Nix store derivations: content-addressed, cacheable, and
deterministic. Same inputs always produce the same outputs, regardless of
when or where you build them. You can diff the rendered manifests between
any two configurations and see exactly what changed, down to the individual
YAML resource. No forensic effort required.

### Multiple deployment targets

The same component declarations compile to output for kapp (direct apply),
ArgoCD, or Fleet. Switching deployment strategy is a single option change.
No component code needs to be rewritten. The rendering pipeline transforms
the same intermediate representation into strategy-specific directory
layouts and metadata.

## Who this is for

Catallaxy is for platform engineers and DevOps practitioners who:

- Have felt the pain of managing multi-cluster Kubernetes environments with
  ad-hoc tooling
- Are comfortable with (or willing to learn) Nix as an infrastructure tool
- Want their platform defined in code that is typed, reproducible, and
  reviewable
- Are tired of tribal knowledge and want a single source of truth that
  compiles

If you recognize that Nix's guarantees (purity, reproducibility, lazy
evaluation, composability) are exactly what infrastructure configuration
needs, this project is for you.

## Getting started

See [Install](./start-here/install.md) to set up your environment, then walk
through [Run the Example Lab](./start-here/first-lab.md) to stand up a
working lab.
