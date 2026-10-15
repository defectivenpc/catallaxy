# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://grafana.github.io/helm-charts";
    chart = "tempo";
    version = "1.21.0";
    hash = "sha256-qAqIV12yS0am46ekdrOCT/LYryZh8aHg1Fzc0aBaEbs=";
  };
in
{
  inherit chart;
  version = "1.21.0";
}
