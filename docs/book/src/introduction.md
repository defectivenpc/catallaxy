# Introduction

Catallaxy is a declarative Kubernetes platform built on the NixOS module
system. It lets you define multi-cluster environments entirely in Nix,
producing rendered manifests and runtime tooling as build outputs. No
imperative orchestration required.

## The name

Catallaxy is F.A. Hayek's word for a spontaneous order: a complex,
coordinated system that emerges not from central planning, but from
independent actors following their own rules. In economics, that is the
market. Here, it is your infrastructure.

The word earns its place because it names something functional programmers
already believe.

**Local reasoning** is the payoff of purity. A pure function can be
understood by looking only at it: no hidden state, no action at a distance,
nothing else to hold in your head. Its meaning is complete in isolation, and
because that is true of every part, composing them is safe. You never have
to simulate the whole program to know what one piece does.

The problem with automating operations or making it declarative is that
somethings don't map exactly to a pure function. This challenge has not been
met well by existing solutions. The name catallaxy is to help reinforce the
idea of local reasoning in this project and help motivate the design and
architecture. No participant holds the global picture. Each follows rules
stated locally. The coordinated whole is _emergent_ rather than authored.
Local reasoning and spontaneous order are the same claim viewed from
opposite ends: one about what you must understand, the other about where the
structure comes from.

Infrastructure is normally the opposite. The deployment order lives in a
runbook. The reason a component installs third is that someone typed `3`. To
know whether a change is safe you have to hold the whole system in your
head, because the couplings are not written down anywhere you can read.

Catallaxy takes the functional position instead. Think about your
architecture as a set of components like cert-manager, ArgoCD, Prometheus,
Kanidm, your own applications. Each is a self-contained declaration. It
defines its own options, its own defaults, the manifests it emits, and the
conditions it needs. **None of them knows the deployment plan.** You can
evaluate one on its own, against a fixture cluster, and reason about it
completely.

When we define things with such a structure then many of the other problems
we experience like managing the complex order of deploying components goes
away. Or I should say that it becomes derivable and automatable. So while it
still has to be solved it can be solved as one single general solution. A
global algorithm can find the install waves from dependency declarations.
There is no imperative glue and no ordering logic scattered across shell
scripts. Parts declare what they need, reference what they depend on, and
the system resolves it at build time.

> **The unit is called a floe.** Think of a floe like a helm chart except
> with structure. Part of the problem with helm charts was that it's
> templating engine not only makes templating difficult for complex
> patterns, but that it didn't maintain structure for consumers of a helm
> chart. With a floe the structure is maintained throughout. It is a typed
> module: an option surface, the manifests it emits, and an interface other
> floes can read. A floe can be shared and distributed allowing authors to
> write a general solution for how to deploy a thing while also providing
> guard rails for the consumers of the floe. Something that isn't built into
> helm charts. You can write a floe from scratch or wrap an existing helm
> chart in a floe to make it more easily distributable through nix flakes.

## What it does

The system has two layers:

- **Nix modules** define the configuration DSL, perform type checking,
  resolve cross-references between clusters, and render every manifest at
  build time.
- **A Rust CLI** (`cata`) works with the built description of a lab and
  orchestrates runtime operations: applying manifests, managing secrets, and
  running ops commands.

Because the first layer is a pure function of your configuration, the same
input always produces the same store path: the manifests CI renders are
byte-identical to yours.

## Status

Functional and in active use for a multi-cluster platform across local,
staging and cloud environments. The API continues to go through substantial
architectural changes to find the right abstractions. Expect breaking
changes between minor versions. Feedback and contributions are welcome.

## Where to go from here

- [Why Catallaxy](./why.md): the argument, with the specific failures it is
  answering.
- [Install](./start-here/install.md): two prerequisites.
- [Run the Example Lab](./start-here/first-lab.md): ten minutes, one
  cluster, no cloud account.
- [The Model](./understanding/model.md): lab, cluster, floe, bundle.
