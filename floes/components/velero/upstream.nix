# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://vmware-tanzu.github.io/helm-charts";
    chart = "velero";
    version = "9.0.1";
    hash = "sha256-NVP7yEKFy4ySfXRNJpWJpIyvnmnoxBAqe6TpLtwkBoU=";
  };
in
{
  inherit chart;
  version = "9.0.1";
  crds = upstream.crdsInChart "velero" chart;
}
