# A DigitalOcean Kubernetes cluster, declared as a resource.
#
# This is the case a bundle cannot cover at all (case
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
# implementation.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "doks";
  summary = "A DigitalOcean Kubernetes cluster, declared as a resource for a state-based tool.";

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
        `modules/lab/cluster/default.nix`. Tagging is what makes a leak
        findable: a cluster nobody can list by lab is a cluster nobody notices
        is still running.
      '';
    };

    publishKubeconfigKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "clusters/workload/kubeconfig";
      description = ''
        Key the cluster's kubeconfig is published under once it exists, or
        null to leave it in state.

        This is the join between resources and bundles: the apply produces a
        kubeconfig, the publication writes it into a lab store, and nothing
        invents a second addressing scheme to get it back out. *Which* store
        is resolved — `optional.labStore` — so only the key is written here,
        and it is written twice on purpose: whatever reads the kubeconfig back
        names the same key, and nothing can derive it from this cluster's name
        because the two clusters have different names.
      '';
    };
  };

  # It installs into a cluster like any other member — the management cluster,
  # or whichever one the lab puts it in. `componentsTargetTheCluster` would
  # refuse it otherwise, and it is not exempt for being a resource.
  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Which lab store the kubeconfig lands in, resolved rather than spelled.
  # Optional because publishing is a choice: a lab may create the cluster and
  # leave its kubeconfig in state. Naming a key with no store resolved is
  # refused here rather than producing a publication addressed at nothing.
  optional.labStore = sigs.LAB_SECRET_STORE;

  out.resources = kinds.resources;
  out.publications = kinds.publications;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        labStore = config.floe.requires.labStore;
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

          outputs = [
            "id"
            "endpoint"
            "kube_config"
            "cluster_subnet"
            "service_subnet"
          ];

          phase = "before-clusters";
        };

        config.floe.out.publications = lib.optionalAttrs (inputs.publishKubeconfigKey != null) {
          kubeconfig = {
            resource = "cluster";
            output = "kube_config";
            store =
              if labStore != null then
                labStore.name
              else
                throw (
                  "doks '${inputs.name}': publishKubeconfigKey is "
                  + "'${inputs.publishKubeconfigKey}' and no LAB_SECRET_STORE resolved, so there "
                  + "is nowhere to publish it. Declare `optional.labStore` on the cluster floe "
                  + "and name the store with `lab.defaults.LAB_SECRET_STORE`."
                );
            key = inputs.publishKubeconfigKey;
          };
        };
      }
    )
  ];
}
