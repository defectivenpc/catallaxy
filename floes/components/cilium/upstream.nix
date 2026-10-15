# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://helm.cilium.io";
    chart = "cilium";
    version = "1.17.2";
    hash = "sha256-l+9fEAb2wb9xAx/HCW/pXW5+MfzbgnSpWk7UOTkpK24=";
  };
in
{
  inherit chart;
  version = "1.17.2";
  # No `crds`: nothing renders this chart's CRDs, so group-scoped resolution
  # would never bring their types into scope. The pin carried an extraction
  # for them anyway, read by nothing.
}
