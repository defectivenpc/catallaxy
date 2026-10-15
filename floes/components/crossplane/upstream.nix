# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://charts.crossplane.io/stable";
    chart = "crossplane";
    version = "1.18.2";
    hash = "sha256-udEOCSnF4fdiCYJ1utlJPLaiLzG8enRY2Z4OYjopESA=";
  };
in
{
  inherit chart;
  version = "1.18.2";
  crds = upstream.crdsInTree "crossplane" {
    owner = "crossplane";
    repo = "crossplane";
    rev = "v1.18.2";
    hash = "sha256-G4Kve77BoQ/RphvggLHIVV+hhkjmTS3q1nQWnDhAjHA=";
    path = "cluster/crds";
  };
}
