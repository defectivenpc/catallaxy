# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://openbao.github.io/openbao-helm";
    chart = "openbao";
    version = "0.16.1";
    hash = "sha256-1O89lZcZXkIJduFA8hy64XVK8bOf6oK/5gR5Ik6dEQg=";
  };
in
{
  inherit chart;
  version = "0.16.1";
}
