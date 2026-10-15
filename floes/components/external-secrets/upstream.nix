# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://charts.external-secrets.io";
    chart = "external-secrets";
    version = "0.15.0";
    hash = "sha256-i5r9ZqdEeTKA1o7kAfviQpxzJwCm+c8JOPE+BH2t/po=";
  };
in
{
  inherit chart;
  version = "0.15.0";
  crds = upstream.release {
    name = "external-secrets";
    url = "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.15.0/deploy/crds/bundle.yaml";
    hash = "sha256-fRPzilKE4AQ0cR06JT6uX0dGAsJ/t3V+kQLOV3lbo0c=";
  };
}
