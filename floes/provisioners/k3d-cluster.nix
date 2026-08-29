# A k3d cluster, as an ordinary floe. Nothing about it is a special case:
# it takes inputs, provides a signature, and emits an output kind.
#
# The provisioner is not a closed set. A Talos cluster, a managed cloud
# cluster, or one that already exists is another floe providing
# KUBERNETES_CLUSTER, and no member changes.
{
  lib,
  floe,
  sigs,
  kinds,
}:

floe.mkFloe {
  name = "k3d-cluster";

  inputs = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name, as members and the kubeconfig see it. Required.";
    };

    instanceName = lib.mkOption {
      type = lib.types.str;
      description = ''
        What k3d calls the cluster's containers. Distinct from `name`
        because two labs may each hold a cluster called `app` on one
        docker host, and the container names would collide.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.31";
      description = "Kubernetes minor version this cluster answers as.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "rancher/k3s:v1.31.4-k3s1";
      description = "k3s node image. Pinned, not floating: a lab is reproducible or it is not.";
    };

    podSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.244.0.0/16";
      description = ''
        Pod CIDR. A decision, written down, not derived from the cluster's
        name: renaming a cluster would then silently move a running one's
        subnet.
      '';
    };

    serviceSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.96.0.0/12";
      description = "Service CIDR. Same reasoning as `podSubnet`.";
    };
  };

  provides.cluster = sigs.KUBERNETES_CLUSTER;
  out.cluster = kinds.cluster;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        # The assembly point. Both the signature and the output kind are
        # projections of this one node, so a changed input moves what
        # deploys and what members read together. Computing the context
        # twice is exactly what the projection rule forbids.
        options.kubeContext = lib.mkOption {
          type = lib.types.str;
          description = "kubectl context name k3d writes for this cluster.";
        };

        config.kubeContext = "k3d-${inputs.instanceName}";

        config.floe.provides.cluster = {
          inherit (inputs)
            name
            version
            podSubnet
            serviceSubnet
            ;
          context = config.kubeContext;
        };

        config.floe.out.cluster = {
          inherit (inputs) name;
          provisioner = "k3d";
          provider = "docker";
          kubeContext = config.kubeContext;

          kubernetes = {
            distribution = "k3s";
            inherit (inputs) version;
            controlPlanes = 1;
            workers = 0;
          };

          network = {
            inherit (inputs) podSubnet serviceSubnet;
          };

          k3d = {
            clusterName = inputs.instanceName;
            inherit (inputs) image;

            # Which docker network the cluster joins is a lab fact — the
            # cluster does not know what else shares it. The lab fills it in.
            network = null;

            # Traefik comes from the gateway floe, at a version this lab
            # pins, so the one k3s bundles would be a second ingress nobody
            # declared. The rest of k3s's batteries stay in: a floe that
            # needs Cilium or OpenEBS turns the conflicting one off itself.
            noTraefik = true;
            noServiceLB = false;
            noFlannel = false;
            noLocalStorage = false;

            ports = [ ];
            extraApiServerArgs = [ ];
            extraVolumes = [ ];
            autoDeployManifests = [ ];
          };
        };
      }
    )
  ];
}
