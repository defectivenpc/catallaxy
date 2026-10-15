# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://traefik.github.io/charts";
    chart = "traefik";
    version = "35.2.0";
    hash = "sha256-E6CY8pKAhLhRuJL1ZtgUXSHlcLVyb0+Nhbe6kFvryD0=";
  };
in
{
  inherit chart;
  version = "35.2.0";
}
