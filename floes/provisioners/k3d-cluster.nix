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
  ...
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

    disableFlannel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the cluster with no CNI at all.

        The nodes then stay NotReady until something provides one, which is
        the point: a cluster carrying both flannel and a replacement is a
        manifest set that could never work, and the two would each write their
        own datapath rules over the other's.

        Set this alongside an `autoDeployManifests` entry that installs the
        replacement. Setting it alone produces a cluster that never comes up.
      '';
    };

    autoDeployManifests = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Filename k3s sees it under, without the extension.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              description = "Store path of the manifest to mount.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Manifests k3s applies at startup, before the node is Ready.

        For the one case a floe cannot cover: something the cluster needs in
        order to finish starting. A CNI is the whole of that case today — a
        floe's bundles are applied to a cluster that is already up, so a floe
        providing the network would have to require the cluster that cannot
        start without it.

        Anything that can wait for a running cluster belongs in a floe, where
        it gets ordering, readiness and drift handling. This gets none of
        those: k3s applies it once and nothing manages it afterwards, which is
        why `floes.cilium` also installs itself as an ordinary release.
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

          # k3s ships ServiceLB, so a LoadBalancer Service gets the node's own
          # address and the gateway is reached on 80 and 443. That is the same
          # fact `edge` projects outward, read from the other side.
          assignsLoadBalancers = true;
        };

        config.floe.out.cluster = {
          inherit (inputs) name;
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

          # The lab is this cluster's edge: it runs on the lab's own docker
          # network, so the proxy reaches it by container name. RFC 0005 §6.4.
          #
          # The server node rather than a published port, because the proxy
          # and the cluster share a network and the port a k3d cluster
          # publishes to the *host* is a different thing entirely.
          edge = {
            mode = "proxy";
            backend = "k3d-${inputs.instanceName}-server-0";

            # k3s's ServiceLB binds these on the node itself, so the gateway's
            # LoadBalancer Service is reachable at the node's name on the
            # ordinary ports. A provisioner without it answers a NodePort.
            httpPort = 80;
            httpsPort = 443;
          };

          config.k3d = {
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
            noLocalStorage = false;

            # The lab's call, not this floe's. It used to be hardcoded false
            # with a comment saying a floe that needs Cilium turns it off
            # itself — which described a writeback from floe to cluster that
            # the link graph has no direction for, and which is what kept
            # cilium unmigrated.
            noFlannel = inputs.disableFlannel;

            ports = [ ];
            extraApiServerArgs = [ ];
            extraVolumes = [ ];
            inherit (inputs) autoDeployManifests;
          };
        };
      }
    )
  ];
}
