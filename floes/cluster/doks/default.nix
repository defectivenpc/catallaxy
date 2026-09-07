# A DigitalOcean Kubernetes cluster, declared as a resource — RFC 0003.
#
# This is the case the reconcile camp cannot cover at all (RFC 0003 §2, case
# 1): before a cluster exists there is no reconciler, no CRD, and nowhere to
# put a credential. Something has to make the first one, and this is it.
#
# It does not *provide* `KUBERNETES_CLUSTER`. The cluster it creates is a
# separate `lab.clusters` entry using `floes.external-cluster`, because the
# thing that declares a cluster into existence and the cluster itself are two
# nodes in the lab: the first is installed somewhere, the second is installed
# *into*. Collapsing them would make a cluster a member of itself.
#
# Nothing here names OpenTofu. `digitalocean` and `digitalocean_kubernetes_cluster`
# are the registry's vocabulary — a borrowed namespace, not a borrowed
# implementation (RFC 0003 §9).
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "doks";

  inputs = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name at the provider. Also the resource's own name.";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "nyc3";
      description = "DigitalOcean region slug.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      example = "1.31.1-do.4";
      description = ''
        DOKS version slug, which is not a Kubernetes version.

        Required and pinned: the provider accepts a prefix like `1.31.` and
        resolves it to whatever is current, so a lab that wrote one would get
        a different cluster on different days and call it reproducible.
      '';
    };

    nodeSize = lib.mkOption {
      type = lib.types.str;
      default = "s-2vcpu-2gb";
      description = "Droplet size slug for the default node pool.";
    };

    nodeCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Nodes in the default pool.";
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Tags applied to the cluster.

        The lab adds its own before these reach the provider — see
        `modules/lab/cluster.nix`. Tagging is what makes a leak findable: a
        cluster nobody can list by lab is a cluster nobody notices is still
        running.
      '';
    };

    publishKubeconfigTo = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            store = lib.mkOption {
              type = lib.types.str;
              description = "A `lab.secrets.stores` entry the kubeconfig lands in.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              description = "Key inside that store.";
            };
          };
        }
      );
      default = null;
      description = ''
        Where the cluster's kubeconfig is published once it exists.

        This is the join between the two camps (RFC 0003 §7): the apply
        produces a kubeconfig, the publication writes it into a store the lab
        already declares, and nothing invents a second addressing scheme to
        get it back out.
      '';
    };
  };

  # It installs into a cluster like any other member — the management cluster,
  # or whichever one the lab puts it in. `componentsTargetTheCluster` would
  # refuse it otherwise, and it is not exempt for being a different camp.
  requires.cluster = sigs.KUBERNETES_CLUSTER;

  out.resources = kinds.resources;
  out.publications = kinds.publications;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.out.resources.cluster = {
          provider = "digitalocean";
          type = "digitalocean_kubernetes_cluster";

          inputs = {
            inherit (inputs) name region;
            version = inputs.version;
            tags = inputs.tags;

            node_pool = {
              name = "${inputs.name}-default";
              size = inputs.nodeSize;
              node_count = inputs.nodeCount;
            };
          };

          # Declared, never inferred. `kube_config` is what the publication
          # below reads; `cluster_subnet` and `service_subnet` are read back so
          # the apply can be checked against what the lab decided rather than
          # sampled — see the note on the lab side.
          outputs = [
            "id"
            "endpoint"
            "kube_config"
            "cluster_subnet"
            "service_subnet"
          ];

          # Nothing exists before it. A cluster is the case that forced this
          # phase to exist at all.
          phase = "before-clusters";
        };

        config.floe.out.publications = lib.optionalAttrs (inputs.publishKubeconfigTo != null) {
          kubeconfig = {
            resource = "cluster";
            output = "kube_config";
            inherit (inputs.publishKubeconfigTo) store key;
          };
        };
      }
    )
  ];
}
