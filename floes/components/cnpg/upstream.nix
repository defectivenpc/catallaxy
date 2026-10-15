# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://cloudnative-pg.github.io/charts";
    chart = "cloudnative-pg";
    version = "0.23.0";
    hash = "sha256-KCbQLH62HiY45GI56GqlTKFBBpBXKrAlh558wnRvLYk=";
  };
in
{
  inherit chart;
  version = "0.23.0";
  crds = upstream.crdsInTree "cnpg" {
    owner = "cloudnative-pg";
    repo = "cloudnative-pg";
    rev = "v1.25.0";
    hash = "sha256-pU8OgGmRzZEfcMOhMHXhwK+oA/6zyj7F7QZ0ZNJIjsQ=";
    path = "config/crd/bases";
  };
}
