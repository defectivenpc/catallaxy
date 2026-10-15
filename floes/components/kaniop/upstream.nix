# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "oci://ghcr.io/pando85/helm-charts";
    chart = "kaniop";
    version = "0.11.1";
    hash = "sha256-7BCNK34d7GV9EVyjDx3lVXuD9L5RIdaE8vuItNkFz5Q=";
  };
in
{
  inherit chart;
  version = "0.11.1";
  crds = upstream.crdsInChart "kaniop" chart;
}
