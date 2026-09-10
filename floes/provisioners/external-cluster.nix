# A cluster something else brings into existence.
#
# RFC 0005 §2 calls this "providing without running": the floe answers
# `KUBERNETES_CLUSTER` like any provisioner, and `cata` creates nothing. What
# makes it a lab cluster is that a lab names it and installs into it.
#
# It covers both ways a cluster arrives without this machine making it:
# reconciled from a CR by a controller in another cluster (Crossplane, Cluster
# API), or applied by a state-based tool (RFC 0003). Neither is a special
# case here, because the difference is *who acts*, and in both cases the
# answer is "not the lab".
#
# The lab still has to know *when* it exists. That is the management cluster's
# `provisions` declaration, not this floe's business — a cluster cannot say
# who creates it without naming something outside itself, and RFC 0005 §6.2
# forbids exactly that.
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
        (RFC 0005 §6.3) even though the cluster's endpoint is not.
      '';
    };

    madeBy = lib.mkOption {
      type = lib.types.str;
      example = "crossplane on 'mgmt'";
      description = ''
        What brings it into existence, for the operator reading a plan.

        Free text and never dispatched on. A `create-cluster` step that does
        nothing reads as broken; one that says what it is waiting for reads as
        waiting.
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

    kubeconfigFrom = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            store = lib.mkOption {
              type = lib.types.str;
              description = "A `lab.secrets.stores` entry the kubeconfig is published to.";
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
        Where this cluster's kubeconfig is published, when a state-based
        apply is what produced it (RFC 0003 §7).

        Null for a cluster a controller in another cluster reconciles: there
        the kubeconfig is in a connection Secret and the lab reaches it
        through the management cluster's `provisions` declaration instead.
        One of the two has to say how the cluster becomes reachable, and a
        lab check refuses one that says neither — a cluster the lab deploys
        to and has no kubeconfig for fails at the first kubectl call with a
        context that does not exist.
      '';
    };

    edgeMode = lib.mkOption {
      type = lib.types.enum [
        "self"
        "none"
      ];
      default = "self";
      description = ''
        Who fronts it — RFC 0005 §6.4.

        Never `proxy`: the lab's proxy reaches backends on its own docker
        network, and a cluster this lab did not create is not on it. `self`
        says the cluster is its own edge, which is what a managed cluster with
        a LoadBalancer is.
      '';
    };
  };

  provides.cluster = sigs.KUBERNETES_CLUSTER;
  out.cluster = kinds.cluster;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
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

        config.floe.out.cluster = {
          inherit (inputs) name;

          # Not `docker`. Read by `modules/lab/plan.nix` to decide whether the
          # cluster joins the lab's network, and this one does not — so the
          # `needs lab.network` edge drops and a lab of nothing but these
          # makes no docker network at all.
          provider = "external";

          kubeContext = inputs.context;

          kubernetes = {
            inherit (inputs) distribution version;
            # Unknown and not guessed. Whoever made it decided; the drift
            # report compares what it finds against the record, and a record
            # claiming one control plane would report drift on every cluster
            # that has three.
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
            inherit (inputs) madeBy kubeconfigFrom;
          };
        };
      }
    )
  ];
}
