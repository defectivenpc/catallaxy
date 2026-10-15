# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://prometheus-community.github.io/helm-charts";
    chart = "kube-prometheus-stack";
    version = "72.5.0";
    hash = "sha256-o/Yzswcv3ydTq6rrP+Ot9SeylGD6N0Bi9WB6GcOVTx4=";
  };
in
{
  inherit chart;
  version = "72.5.0";
  crds = upstream.release {
    name = "prometheus";
    url = "https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.82.2/stripped-down-crds.yaml";
    hash = "sha256-3mkDUyIqXqtAkpHOlfCs7DNw90/x1+B9SSH/hsn56CE=";
  };
}
