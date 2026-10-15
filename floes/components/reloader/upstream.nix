# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://stakater.github.io/stakater-charts";
    chart = "reloader";
    version = "2.2.14";
    hash = "sha256-kZU0Qdf959SbMOJLCuUrjM1mtYbtv+gfttVi17ZCZo0=";
  };
in
{
  inherit chart;
  version = "2.2.14";
}
