# A cluster something else brings into existence.
#
# it calls this "providing without running": the floe answers
# `KUBERNETES_CLUSTER` like any provisioner, and `cata` creates nothing. What
# makes it a lab cluster is that a lab names it and installs into it.
#
# It covers both ways a cluster arrives without this machine making it:
# reconciled from a CR by a controller in another cluster (Crossplane, Cluster
# API), or applied by a state-based tool. Neither is a special
# case here, because the difference is *who acts*, and in both cases the
# answer is "not the lab".
#
# The lab still has to know *when* it exists. That is the management cluster's
# `provisions` declaration, not this floe's business — a cluster cannot say
# who creates it without naming something outside itself, which is exactly
# what the stratification forbids.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "external-cluster";
  summary = "A cluster something else brings into existence, which this lab installs into.";

  inputs = {
    wait = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        How long to wait for the API server to answer once the cluster has
        been created.

        Here rather than on the cluster, because how long a cluster takes to
        come up is a property of what makes it. The wait for an *apply* to
        settle belongs to whatever applies, and is `DELIVERY_POLICY`'s.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name, as members and the kubeconfig see it. Required.";
    };

    context = lib.mkOption {
      type = lib.types.str;
      description = ''
               kubectl context this cluster answers on.

               A decision, not a discovery: `cata` writes the kubeconfig under this
               name after fetching it, rather than taking whatever the producing tool
               called it. That is what keeps `KUBERNETES_CLUSTER.context` concrete
        even though the cluster's endpoint is not.
      '';
    };

    madeBy = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "a hand, once, in 2019";
      description = ''
        What brings it into existence, for the operator reading a plan.

        Free text and never dispatched on, for a cluster nothing in this lab
        creates. One that *is* created by something here says so through
        `optional.provisioning` instead, where the planner can read it — and
        a cluster that answers neither is refused, because a cluster nothing
        creates and nothing fetches a kubeconfig for is a context that will
        not exist.

        A `create-cluster` step that does nothing reads as broken; one that
        says what it is waiting for reads as waiting.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.31";
      description = "Kubernetes minor version this cluster answers as.";
    };

    distribution = lib.mkOption {
      type = lib.types.str;
      default = "kubernetes";
      description = "What it runs, for the record and for drift reporting.";
    };

    podSubnet = lib.mkOption {
      type = lib.types.str;
      description = ''
        Pod CIDR.

        Required rather than defaulted, because for a cluster this lab does
        not create, a default would be a guess about somebody else's network
        that every member then renders against. Declared here and checked
        against the cluster it turns out to be.
      '';
    };

    serviceSubnet = lib.mkOption {
      type = lib.types.str;
      description = "Service CIDR. Same reasoning as `podSubnet`.";
    };

    assignsLoadBalancers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether a `LoadBalancer` Service gets an address here.

        True by default because every managed Kubernetes offering has a cloud
        controller that assigns one — which is the case this floe mostly
        covers, and the opposite of the bare Talos default.
      '';
    };

    kubeconfigKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "clusters/workload/kubeconfig";
      description = ''
        Key this cluster's kubeconfig is published under, when a state-based
        apply is what produced it. *Which* store is resolved —
        `optional.labStore`.

        Null for a cluster a controller in another cluster reconciles: there
        the kubeconfig is in a connection Secret and the lab reaches it
        through the management cluster's `provisions` declaration instead. One
        of the two has to say how the cluster becomes reachable, and a lab
        check refuses one that says neither — a cluster the lab deploys to and
        has no kubeconfig for fails at the first kubectl call with a context
        that does not exist.
      '';
    };

    edgeMode = lib.mkOption {
      type = lib.types.enum [
        "self"
        "none"
      ];
      default = "self";
      description = ''
        Who fronts it.

        Never `proxy`: the lab's proxy reaches backends on its own docker
        network, and a cluster this lab did not create is not on it. `self`
        says the cluster is its own edge, which is what a managed cluster with
        a LoadBalancer is.
      '';
    };
  };

  provides.cluster = sigs.KUBERNETES_CLUSTER;

  # And no `CLUSTER_EDGE`. A cluster this lab did not create has no address
  # this lab can derive: there is no container of ours to name, and the
  # endpoint whoever made it published is not something a docker bridge
  # reaches. Declining is the complete answer, and it is what makes the hole
  # a consumer declares for this optional.
  # Zero or one, which is the shape of the question: a cluster this lab
  # creates reads the coordinates of the object that creates it, and one that
  # already existed reads nothing. Optional holes resolve only when a deployer
  # names the provider, which here is the lab saying which cluster runs the
  # controller.
  optional.provisioning = sigs.CLUSTER_PROVISIONING;

  # The other way a kubeconfig arrives: a state-based apply published it into
  # a lab store. Which store is resolved rather than spelled; the key is
  # written on both sides because the publisher and this cluster have
  # different names and neither can derive the other's.
  optional.labStore = sigs.LAB_SECRET_STORE;

  out.clusterDescriptor = kinds.cluster;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        labStore = config.floe.requires.labStore;
      in
      {
        config.floe.provides.cluster = {
          inherit (inputs)
            name
            version
            context
            podSubnet
            serviceSubnet
            assignsLoadBalancers
            ;
        };

        config.floe.out.clusterDescriptor = {
          inherit (inputs) name;

          instanceName = inputs.name;

          kubeContext = inputs.context;
          inherit (inputs) wait;

          kubernetes = {
            inherit (inputs) distribution version;
            controlPlanes = 0;
            workers = 0;
          };

          network = {
            inherit (inputs) podSubnet serviceSubnet;
          };

          edge = {
            mode = inputs.edgeMode;
            backend = null;
            httpPort = 80;
            httpsPort = 443;
          };

          config.external = {
            madeBy =
              let
                by = config.floe.requires.provisioning or null;
              in
              if by != null then "${by.resourceKind}/${by.resourceName}" else inputs.madeBy;

            provisionedBy = config.floe.requires.provisioning or null;

            kubeconfigFrom =
              if inputs.kubeconfigKey == null then
                null
              else if labStore == null then
                throw (
                  "external-cluster '${inputs.name}': kubeconfigKey is "
                  + "'${inputs.kubeconfigKey}' and no LAB_SECRET_STORE resolved, so there is "
                  + "no store to read it from. Declare `optional.labStore` on the cluster floe "
                  + "and name the store with `lab.defaults.LAB_SECRET_STORE`."
                )
              else
                {
                  store = labStore.name;
                  key = inputs.kubeconfigKey;
                };
          };
        };
      }
    )
  ];
}
