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
    chart = "cert-manager";
    version = "1.17.2";
    hash = "sha256-8d/BPet3MNGd8n0r5F1HEW4Rgb/UfdtwqSFuUZTyKl4=";
  };
in
{
  inherit chart;
  version = "1.17.2";
  crds = upstream.release {
    name = "cert-manager";
    url = "https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.crds.yaml";
    hash = "sha256-uV5UEebfhwdm3May91pRmPwFS+YUM5L6KDzfi0BMfzU=";
  };
}
