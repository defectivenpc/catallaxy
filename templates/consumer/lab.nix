# Your topology.
#
# `floes` is catallaxy's set, handed in by `mkLab`. `myFloes` is yours,
# handed in by the flake — a floe is a function, not a module to import, so
# it reaches the lab as an ordinary argument.
{ myFloes }:

{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:

let
  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";
in
{
  lab.name = lib.mkDefault "my-platform";
  lab.dns.zone = lib.mkDefault "example.test";

  lab.clusters.app.floes = {
    cluster = floes.k3d-cluster {
      name = "app";
      instanceName = instanceOf "app";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    # The gateway requires X509_ISSUANCE outright, so every cluster with a
    # gateway has an issuer even when nothing terminates TLS.
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };

    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
    };

    hello = myFloes.hello-world { };
  };
}
