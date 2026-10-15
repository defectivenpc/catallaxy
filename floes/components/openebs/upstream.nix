# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://charts.containeroo.ch";
    chart = "local-path-provisioner";
    version = "0.0.30";
    hash = "sha256-oJrU/MWNYKA3/OhBjX7Py/hDKio4Zs7Ta1qfa+Eo7r4=";
  };
in
{
  inherit chart;
  version = "0.0.30";
}
