/*
  The generated Kubernetes types, at the version a lab runs.

  Everything here is a view over `./generated/`, which `cata-build generate`
  writes. Three readers, between them taking three things:

  - `lib/kubernetes/conform.nix` resolves a resource's own `apiVersion` and
    `kind` to the type its fields are checked against, through
    `generatedTypes.resolveResourceType` over `typesByKind`.
  - `lib/lower/cluster.nix` passes `coreKinds` to the elaborator,
    which hands it to `lib/eval/manifest-autoedges.nix`. There it is a membership
    test: a resource whose kind is not built in needs an ordering edge to
    whichever bundle establishes its CRD.

  This file used to hold a second, hand-written resource type —
  `kubernetesResourceType`, `bundleType`, `helmChartType`, `readyProbeType`,
  `specTypeFor` — about 620 lines describing the same objects the generator
  already describes, and listing their top-level fields by hand. Nothing
  imported any of it. It went when `conform.nix` began resolving the generated
  type directly, which is both less code and more complete: the generated type
  knows `Role.rules` and `Secret.immutable`, and the hand-written one did not.
*/
{
  lib,
  k8sVersion ? "1.31",

  # API group -> generated type file, from `lib/floe-crds.nix`.
  #
  # Required, with no default. `{ }` is a legal and useful answer — it means
  # "the Kubernetes API only", which is all `coreKinds` needs — but a *default*
  # of it would hand a caller a lookup table silently missing every CRD, and
  # `conform.nix` resolving a custom resource against that finds no schema and
  # checks none of its fields. One call site asked for it by accident and the
  # coverage check reported every CRD in the tree as unschema'd.
  crdTypes,
}:

let
  generatedTypes = import ./generated/index.nix { inherit lib; };

  versionedTypes = generatedTypes.withCrds crdTypes (generatedTypes.forVersion k8sVersion);
in
{
  inherit generatedTypes;

  # kind -> every generated type of that kind, across API versions.
  # `resolveResourceType` picks one by `apiVersion`.
  typesByKind = generatedTypes.typesByKind versionedTypes;

  # The kinds an apiserver has without anyone installing a CRD, as a set for
  # membership testing. 141 of them at 1.31.
  coreKinds = generatedTypes.coreKinds versionedTypes;
}
