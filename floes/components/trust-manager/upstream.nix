# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://charts.jetstack.io";
    chart = "trust-manager";
    version = "0.22.1";
    hash = "sha256-No3nepftJ5d9+5eXkgDCR4iAKun46a3rbI+uz4FxGSw=";
  };
in
{
  inherit chart;
  version = "0.22.1";
  crds = upstream.crdsInTemplate "trust-manager" chart;
}
