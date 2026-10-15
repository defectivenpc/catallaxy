# The upstream this floe vendors, pinned.
#
# No chart: the gateway-api project publishes its CRDs as a release artifact,
# which is the whole of what this floe installs. The version is a field and the
# URL is built from it, so the tag the floe reports and the file it installs
# cannot disagree.
{ upstream }:

let
  version = "v1.2.1";
in
{
  inherit version;

  crds = upstream.release {
    name = "gateway-api";
    url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${version}/experimental-install.yaml";
    hash = "sha256-06pnI6MwZ3DP+2Ae4irz012kOs+hylR/wNO84I2tZuc=";
  };
}
