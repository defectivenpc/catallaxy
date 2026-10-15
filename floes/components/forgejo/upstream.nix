# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "oci://codeberg.org/forgejo-contrib";
    chart = "forgejo";
    version = "5.1.0";
    hash = "sha256-NVImZhZY6u1CN4C/6jCXl/SVz35NTtewK+bgGBj3oPE=";
  };
in
{
  inherit chart;
  version = "5.1.0";
}
