# A Talos cluster in docker, as an ordinary floe.
#
# The second provisioner, and the one that shows the first was not a special
# case: it answers the same signature and emits the same kind, and no member
# of a cluster changes when a lab swaps one for the other.
#
# Three things k3d gives for free that this does not, each of which is a field
# below rather than a branch somewhere in the lab:
#
#   - talosctl makes the cluster's network and will not join an existing one,
#     so whatever has to reach the nodes joins *theirs*. `reachableFrom`.
#   - nothing here assigns LoadBalancer addresses, so the gateway is a
#     NodePort and the lab's proxy dials that. `assignsLoadBalancers = false`,
#     and `edge` names the ports.
#   - Talos is configured by machine config, not flags. Where k3d takes a bind
#     mount or a `--k3s-arg`, this takes a patch. `configPatches`.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens needs;
in

floe.mkFloe {
  name = "talos-cluster";
  summary = "A Talos cluster in docker, on a network talosctl makes.";

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

    instanceName = lib.mkOption {
      type = lib.types.str;
      description = ''
        What talosctl calls the cluster's containers. Distinct from `name` for
        the reason k3d's is: two labs may each hold a cluster called `app` on
        one docker host, and the container names would collide.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.31";
      description = ''
        Kubernetes minor version this cluster answers as, written
        major.minor — the schema set manifests are typed against.

        Distinct from `kubernetesVersion`, which is a kubelet image tag and
        needs a patch level. That one is not a version anything validates
        against; this one is not a tag anything can pull.
      '';
    };

    kubernetesVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.31.4";
      description = "Kubelet image tag, written major.minor.patch. Pinned, not floating.";
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Talos node image. Null takes talosctl's own default for its version.";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.5.0.0/24";
      description = ''
        Subnet talosctl makes for the cluster's own network.

        Talos gets one of its own because talosctl will not join a network it
        did not make. Must not overlap the lab's, which the lab's own checks
        do not cover — this network is not one the lab creates.
      '';
    };

    memory = lib.mkOption {
      type = lib.types.str;
      default = "2.0GiB";
      description = "Memory per node.";
    };

    cpus = lib.mkOption {
      type = lib.types.str;
      default = "2.0";
      description = "CPUs per node.";
    };

    workers = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 1;
      description = ''
        Worker nodes.

        At least one unless nothing has to be scheduled. A Talos control plane
        keeps the standard NoSchedule taint, unlike a k3d server node, so a
        cluster with none has nowhere to run a workload — and the symptom is
        every Pod Pending rather than anything naming the taint.
      '';
    };

    podSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.244.0.0/16";
      description = "Pod CIDR. A decision, written down; see the k3d floe.";
    };

    serviceSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.96.0.0/12";
      description = "Service CIDR. Same reasoning as `podSubnet`.";
    };

    configPatches = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Machine config patches applied to every node, each a JSON or YAML
        document.

        This is how Talos is configured at all: registry mirrors, CA trust,
        nameservers, API server arguments and the CNI choice are all machine
        config rather than command line flags.
      '';
    };

    exposedPorts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Host port mappings talosctl publishes, as `host:container`.";
    };

    mounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Bind mounts on every node, as `host:container`.";
    };
  };

  provides.cluster = sigs.KUBERNETES_CLUSTER;

  # talosctl's container naming, which nothing outside this floe knows.
  provides.edge = sigs.CLUSTER_EDGE;

  out.clusterDescriptor = kinds.cluster;
  out.steps = kinds.steps;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        options.kubeContext = lib.mkOption {
          type = lib.types.str;
          description = "kubectl context name talosctl writes for this cluster.";
        };

        options.edge = lib.mkOption {
          type = lib.types.attrs;
          description = "Where the lab's ingress dials this cluster's gateway.";
        };

        config.kubeContext = "admin@${inputs.instanceName}";

        config.edge = {
          backend = "${inputs.instanceName}-controlplane-1";
          httpPort = kinds.gatewayNodePorts.http;
          httpsPort = kinds.gatewayNodePorts.https;
        };

        config.floe.provides.edge = config.edge;

        config.floe.provides.cluster = {
          inherit (inputs)
            name
            version
            podSubnet
            serviceSubnet
            ;
          context = config.kubeContext;

          assignsLoadBalancers = false;
        };

        config.floe.out.steps.create-cluster = {
          kind = "create-cluster";
          description = "Create talos cluster '${inputs.name}'";
          providesCluster = "created";
          after = [ (needs planTokens.lab.network) ];

          params = {
            inherit (inputs) name;
            provisioner = "talos";
          };
        };

        config.floe.out.steps.deploy-manifests = {
          kind = "deploy-manifests";
          description = "Deploy manifests to '${inputs.name}'";
          providesCluster = "deployed";
          afterCluster = "created";

          params = {
            target = inputs.name;
            bootstrap = false;
            kubeContext = config.kubeContext;
          };
        };

        config.floe.out.steps.destroy-cluster = {
          kind = "destroy-cluster";
          direction = "teardown";
          description = "Destroy talos cluster '${inputs.name}'";
          providesCluster = "destroyed";

          params = {
            inherit (inputs) name;
            provisioner = "talos";
            skipIfMissing = true;
          };
        };

        config.floe.out.clusterDescriptor = {
          inherit (inputs) name instanceName;
          kubeContext = config.kubeContext;
          inherit (inputs) wait;

          kubernetes = {
            distribution = "talos";
            inherit (inputs) version;
            controlPlanes = 1;
            inherit (inputs) workers;
          };

          network = {
            inherit (inputs) podSubnet serviceSubnet;
          };

          edge = {
            mode = "proxy";
          }
          // config.edge;

          config.talos = {
            clusterName = inputs.instanceName;
            inherit (inputs)
              image
              subnet
              memory
              cpus
              configPatches
              exposedPorts
              mounts
              ;
            inherit (inputs) kubernetesVersion;

            reachableFrom = [ ];
          };
        };
      }
    )
  ];
}
