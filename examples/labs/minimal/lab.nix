# One cluster, a gateway, and one service behind it.
#
# The whole of what a lab author writes: which floes are in the cluster and
# what to instantiate them with. Ordering is not here because nothing declares
# it — the linker resolves the signatures and the elaborator derives the
# install order from them.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:

let
  # Two labs may each hold a cluster called `app` on one docker host, so the
  # container name carries the lab. `.` is not legal in a k3d cluster name.
  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";
in
{
  lab.name = lib.mkDefault "minimal";
  lab.dns.zone = lib.mkDefault "minimal.test";

  # The cache survives `lab destroy`, so standing this lab back up pulls from
  # disk rather than from the internet.
  lab.registry.enable = lib.mkDefault true;

  # The base lab runs no ingress, so podinfo's route is genuinely unreachable
  # from the host and the endpoint probe is right to say so. `minimal.tls`
  # stands one up and turns this back on; the probe is off here rather than
  # worked around, because a lab publishing no ingress port has nothing to
  # dial.
  lab.verify.endpoints.enable = lib.mkDefault false;

  lab.clusters.app.floes = {
    cluster = floes.k3d-cluster {
      name = "app";
      instanceName = instanceOf "app";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    # Every cluster with a gateway has an issuer: the gateway requires
    # X509_ISSUANCE outright, because a certificate needs one and floe-core
    # has no optional-exactly-one hole. `minimal.local` does not terminate
    # TLS, so nothing signs anything here; `minimal.tls` flips one input.
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };

    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = config.lab.dns.zone;
    };

    podinfo = floes.podinfo { };
  };
}
