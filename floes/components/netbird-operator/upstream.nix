# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "oci://ghcr.io/netbirdio/helm-charts";
    chart = "netbird-operator";
    version = "0.7.0";
    hash = "sha256-60er+LAeq/cxNXQVwwae58hAaIpV5p+J4dI2zbSzoZQ=";
  };
in
{
  inherit chart;
  version = "0.7.0";
  crds = upstream.crdsInChart "netbird-operator" chart;
}
