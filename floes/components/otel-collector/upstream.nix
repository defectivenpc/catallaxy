# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://open-telemetry.github.io/opentelemetry-helm-charts";
    chart = "opentelemetry-collector";
    version = "0.156.0";
    hash = "sha256-rltQ1AOliiNVwhBkU24G0c4uRZj46TUepGG9Oh38GQg=";
  };
in
{
  inherit chart;
  version = "0.156.0";
}
