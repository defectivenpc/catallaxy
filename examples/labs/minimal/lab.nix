# One cluster, a gateway, and one service behind it.
#
# The whole of what a lab author writes: which floes are in the cluster and
# what to instantiate them with. Ordering is not here because nothing declares
# it — the linker resolves the signatures and the elaborator derives the
# install order from them.
{
  lib,
  catallaxy,
  cataCharts,
  k8sSpecs,
  floeSet,
  config,
  ...
}:

let
  inherit (catallaxy) floe sigs kinds;

  args = {
    inherit
      lib
      floe
      sigs
      kinds
      ;
  };

  k3dCluster = import floeSet.provisioners.k3d-cluster args;
  gatewayApiCrds = import floeSet.cluster.gateway-api-crds args;
  gateway = import floeSet.cluster.gateway args;
  podinfo = import floeSet.cluster.podinfo args;

  # Two labs may each hold a cluster called `app` on one docker host, so the
  # container name carries the lab. `.` is not legal in a k3d cluster name.
  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";
in
{
  lab.name = lib.mkDefault "minimal";
  lab.dns.zone = lib.mkDefault "minimal.test";

  lab.clusters.app.floes = {
    cluster = k3dCluster.instantiate {
      name = "app";
      instanceName = instanceOf "app";
    };

    gateway-api = gatewayApiCrds.instantiate {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    gateway = gateway.instantiate {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = config.lab.dns.zone;
    };

    podinfo = podinfo.instantiate { };
  };
}
