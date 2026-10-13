# Roadmap

## Next

- **A cluster authored on its own.** `cata cluster up` acts on one cluster's
  document with no lab, and a cluster is still _written_ inside one: the
  module reads three things of the lab around it — its name, the proxy a
  cluster may be reached through, and the link. An `examples/clusters/`
  fixture needs an answer for each, which is a small shim and not yet
  written.
- **The document's shape declared once.** The cluster document is a Nix
  emission and a Rust struct, bound by a check that parses every lab's
  document rather than by one declaration both sides are generated from.
- **`argocd-tls-certs-cm`.** Argo takes repository CAs only from that
  ConfigMap, mounted without `optional`, and nothing declares one — so a
  gitops lab pointing Argo at an in-lab HTTPS repository needs the argocd
  floe to declare it. Today's `gitops.local` works because the bootstrap
  applies over plain HTTP inside the cluster.

- **`kind:` and `floe:` anchors.** Both are implemented in the graph
  resolver but inert, because the wave builder passes `null` for those
  fields. Wiring them up makes "after every CRD bundle" expressible without
  naming each one.
- **`cata images lock`.** Resolve tags to digests and write a lockfile, so
  `requireDigest` is adoptable without hand-collecting hashes.
- **Floe-declared lint checks.** `lab.lint.checks` is lab-scope only. A floe
  that knows an invariant about its own manifests cannot express it except
  as an assertion over the configuration.

## Later

- **Talos on bare metal.** `cluster.provisioner = "talos"` exists today, but
  only as Talos-in-Docker for local development, driven by `talosctl`. There
  is no provisioner module for real hardware.
- **Air-gapped registry rewriting**, rewrite every image reference to a
  mirror at render time rather than relying on containerd config.
- **Per-floe network policies**, built-in floes declaring their own
  cross-namespace allow rules when `networkPolicies.enable` is on. Today the
  default-deny lands and each floe's rules are the operator's problem.
- **Richer SBOMs.** `cluster.out.sbom` reports each enabled floe and its
  version. It does not yet read the rendered manifests, so images pinned
  inside a Helm chart's own values are not counted.

## Ideas

Not committed to, and each would want a design discussion first.

- A test harness for lab configurations beyond eval and lint, spinning up a
  lab in CI and asserting on live state.
- Progressive delivery integration (Flagger or Argo Rollouts) as a
  first-class floe with typed analysis templates.
- Cost attribution from the declared topology.

## Contributing

Any of the above is a reasonable place to start. See
[Contributing](./contributing.md).
