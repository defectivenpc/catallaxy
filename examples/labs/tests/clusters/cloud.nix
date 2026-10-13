# A cluster that creates a cloud cluster, and the cloud cluster itself.
#
# The pair is the cloud testing ladder's top rung without a cloud under it:
# `home` runs the `doks` floe, which publishes the new cluster's kubeconfig
# into a lab store, and `workload`'s claim reads it back. Neither cluster
# names the other — the store is what they share, and the claim is a
# retrieval.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;

  platform = {
    kapp = floes.kapp { };
    gateway-api = floes.gateway-api-crds { };
    cert-manager = floes.cert-manager { };
    gateway = floes.gateway { };
  };
in
{
  home = mkClusterFloe {
    name = "cloud-home";
    summary = "The cluster that asks a cloud for another one.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    # Local, created here, and fronted — so its claim has an address to give.
    optional.edge = sigs.CLUSTER_EDGE;

    # And the lab's root, so the issuer here signs from it rather than minting
    # a second over the Secret `cata lab up` seeded.
    optional.labCa = sigs.LAB_CA;

    # Where `doks` publishes the kubeconfig. Optional because publishing is a
    # choice; the lab wires it with `lab.defaults.LAB_SECRET_STORE`, and the
    # `workload` claim that reads it back resolves the same store beside the
    # cluster rather than through one.
    optional.labStore = sigs.LAB_SECRET_STORE;

    provides = {
      delivery = sigs.DELIVERY_POLICY;
      exposure = sigs.HOST_EXPOSURE;
    };

    exports = {
      delivery = "kapp/delivery";
      exposure = "gateway/exposure";
    };

    units =
      _:
      platform
      // {
        doks = floes.doks {
          name = "cloud-workload";
          version = "1.31.1-do.4";
          nodeCount = 2;
          # Which store is resolved; `cloud`'s `lab.defaults` wires it. The
          # key is written here and again on `workload`'s claim, because the
          # two clusters have different names and neither can derive the
          # other's.
          publishKubeconfigKey = "clusters/workload/kubeconfig";
        };
      };
  };

  # Its own edge, which it says by exporting no exposure. A cluster in a cloud
  # has a LoadBalancer with a real address and is reached at it; the lab's
  # ingress dials backends on its own docker network, which this cluster is
  # not on, so there is nothing for the lab to answer for here.
  #
  # It used to export the exposure and be kept out of the routing by
  # `lab.edges.workload.mode = "self"` — two statements that had to agree, and
  # the proxy's host map was built from the second. One statement now, and the
  # ingress refuses a lab that exports an exposure its provisioner cannot give
  # an address for.
  workload = mkClusterFloe {
    name = "cloud-workload";
    summary = "The cloud cluster, with a workload behind a gateway.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    optional.labCa = sigs.LAB_CA;

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "kapp/delivery";

    units =
      _:
      platform
      // {
        podinfo = floes.podinfo { };
      };
  };
}
