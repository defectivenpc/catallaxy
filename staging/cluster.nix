# `minimal.local`'s `app` cluster, expressed in the floe interface.
#
# Three units and one link. Nothing here is a lab: no plan graph, no host
# services, no DNS, no registry, no secrets, no provisioning.
{
  lib,
  catallaxy,
  cataCharts,
  k8sSpecs,
}:

let
  inherit (catallaxy)
    floe
    sigs
    kinds
    policies
    ;

  args = {
    inherit
      lib
      floe
      sigs
      kinds
      ;
  };

  k3dCluster = import ./floes/k3d-cluster.nix args;
  gatewayApiCrds = import ./floes/gateway-api-crds.nix args;
  gateway = import ./floes/gateway.nix args;
  podinfo = import ./floes/podinfo.nix args;
in
floe.link {
  units = {
    # `instanceName` is what `minimal.local` names the k3d containers, so the
    # rendered context matches the reference build and the two are comparable.
    cluster = k3dCluster.instantiate {
      name = "app";
      instanceName = "minimal-local-app";
    };

    gateway-api = gatewayApiCrds.instantiate {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    gateway = gateway.instantiate {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = "minimal.test";
    };

    podinfo = podinfo.instantiate { };
  };

  policies = [
    policies.oneCluster
    policies.componentsTargetTheCluster
    policies.needsNameSiblings
    policies.backsNameOwnBundles
  ];
}
