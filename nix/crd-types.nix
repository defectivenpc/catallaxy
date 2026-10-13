/*
  Which CRDs get generated Nix types, and what they are generated from.

  Each source is the *same pinned artifact the floe installs* — the chart's own
  `crds/` directory, or the release YAML it fetches — so the types describe the
  CRDs that will actually be applied. Generating from a separately pinned copy
  is how the types come to describe a Kubernetes nobody is running.

  `cata-build generate` files the output by API group rather than by source name, so
  one entry here can produce several `crds/<group>.nix` files: `crossplane`
  defines three groups. Two entries defining the same `group/Kind` is refused
  rather than resolved.

  A kind outside these sources has no type, and a bundle that establishes its
  group has to say so. Adding an entry is how a kind becomes checkable;
  `argocd` and `cilium` are absent because no bundle establishes their groups,
  so group-scoped resolution would never bring them into scope.
*/
{
  lib,
  cataCharts,
  k8sSpecs,
}:

let
  fromCharts = [
    "cert-manager"
    "cnpg"
    "crossplane"
    "external-dns"
    "external-secrets"
    "kaniop"
    "netbird-operator"
    "prometheus"
    "redis-operator"
    "trust-manager"
    "velero"
  ];

  missing = lib.filter (name: (cataCharts.${name}.crds or null) == null) fromCharts;
in
if missing != [ ] then
  throw (
    "catallaxy: no CRD source for "
    + lib.concatStringsSep ", " missing
    + ".\n\nEvery chart named here must carry a `crd` definition in "
    + "`lib/charts.nix`, since that is the artifact its types are generated "
    + "from. A chart that stopped shipping CRDs needs removing from both."
  )
else
  lib.genAttrs fromCharts (name: cataCharts.${name}.crds)
  // {
    inherit (k8sSpecs.standaloneCrds) gateway-api;
  }
