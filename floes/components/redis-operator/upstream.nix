# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://ot-container-kit.github.io/helm-charts";
    chart = "redis-operator";
    version = "0.18.2";
    hash = "sha256-n6mICvnMxLXLcRN93oND0EzF6qn/EjXiJnOunXJQLw4=";
  };
in
{
  inherit chart;
  version = "0.18.2";
  crds = upstream.crdsInChart "redis-operator" chart;
}
