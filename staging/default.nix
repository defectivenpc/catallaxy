# Staging area for the floe interface (RFC 0001), kept out of `floes/` and
# `examples/labs/` because it satisfies neither's contract yet. See README.md.
{
  lib,
  pkgs,
  cataCharts,
  k8sSpecs,
}:

let
  catallaxy = import ../lib/floe-catallaxy { inherit lib pkgs; };

  link = import ./cluster.nix {
    inherit
      lib
      catallaxy
      cataCharts
      k8sSpecs
      ;
  };

  # bundles + link edges -> cluster metadata. The whole cluster picture, and
  # the only place the two floes' outputs are joined.
  cluster = catallaxy.elaborateCluster {
    linkResult = link;
    coreKinds = (import ../modules/lab/cluster/lib/kubernetes/types.nix { inherit lib; }).coreKinds;
  };
in
{
  # The IR: `{ provides; out; graph; phases; wiring; }`, all of it plain data.
  inherit link cluster;

  manifests = catallaxy.renderCluster {
    name = "app";
    owner = "staging.app";
    inherit cluster;
  };
}
