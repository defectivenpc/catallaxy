# The upstream this floe vendors, pinned.
#
# One pin, read by the floe's own `chart` default and — when there are
# CRDs — by the generator that writes `crds/<group>.nix` beside this file.
# Generating types from a separately pinned copy is how types come to
# describe a Kubernetes nobody is running.
{ upstream }:

let
  chart = upstream.helm {
    repo = "https://argoproj.github.io/argo-helm";
    chart = "argo-cd";
    version = "8.0.2";
    hash = "sha256-fpBQ8guYb9mY/r5WEzXeSFyCkDcac6PX74+M+MdNu98=";
  };
in
{
  inherit chart;
  version = "8.0.2";
  # No `crds`: nothing renders this chart's CRDs, so group-scoped resolution
  # would never bring their types into scope. The pin carried an extraction
  # for them anyway, read by nothing.
}
