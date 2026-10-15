# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://seaweedfs.github.io/seaweedfs/helm";
    chart = "seaweedfs";
    version = "4.0.0";
    hash = "sha256-8iW/unqfCVGeYFy8XPh7E9chH6bzyX3u+x3lgxSa6e0=";
  };
in
{
  inherit chart;
  version = "4.0.0";
}
