# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://kubernetes-sigs.github.io/external-dns";
    chart = "external-dns";
    version = "1.16.1";
    hash = "sha256-0Hda7wKttTw9o2h21xFg0DB9DxEceh+XUEJ5mzBuM78=";
  };
in
{
  inherit chart;
  version = "1.16.1";
  crds = upstream.crdsInChart "external-dns" chart;
}
