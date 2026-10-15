# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://helm.goharbor.io";
    chart = "harbor";
    version = "1.19.1";
    hash = "sha256-EyzxTVfMZsLIC8KPBdT8AHtR8pVe3DkJ5I4btlTnsnE=";
  };
in
{
  inherit chart;
  version = "1.19.1";
}
