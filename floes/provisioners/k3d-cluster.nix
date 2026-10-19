# A k3d cluster, as an ordinary floe. Nothing about it is a special case:
# it takes inputs, provides a signature, and emits an output kind.
#
# The provisioner is not a closed set. A Talos cluster, a managed cloud
# cluster, or one that already exists is another floe providing
# KUBERNETES_CLUSTER, and no member changes.
{
  lib,
  pkgs,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens needs;
  # Reads are the bulk of the traffic and the least of the interest.
  # Dropping them first is what keeps the log readable at `Metadata`.
  auditPolicyFor =
    level:
    pkgs.writeText "audit-policy.yaml" (
      builtins.toJSON {
        apiVersion = "audit.k8s.io/v1";
        kind = "Policy";
        rules = [
          {
            level = "None";
            verbs = [
              "get"
              "list"
              "watch"
            ];
          }
          { inherit level; }
        ];
      }
    );
in
floe.mkFloe {
  name = "k3d-cluster";
  summary = "A k3d cluster on the operator's docker host.";

  inputs = {
    auditLogging = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Record what the API server was asked to do.

              Off by default: it is the one control here that costs something at
              runtime, and on a laptop lab the log is usually read never. Turned
              on, it is the only way to answer what changed a resource after the
              fact.

              Here rather than on the cluster, because every field of it is a
              flag and a mount for an API server *this floe* creates — a managed
              control plane logs through its provider, and a cluster this lab did
              not make has no server to pass flags to. The cluster module used to
              hold it and reach into this variant through a per-provisioner hook
              to inject it.
            '';
          };

          level = lib.mkOption {
            type = lib.types.enum [
              "Metadata"
              "Request"
              "RequestResponse"
            ];
            default = "Metadata";
            description = ''
              How much of each request is recorded.

              `Metadata` is who, what and when. `Request` adds the submitted
              object and `RequestResponse` the returned one — both of which write
              Secret contents to the log, which is why neither is the default.
            '';
          };

          maxAgeDays = lib.mkOption {
            type = lib.types.ints.positive;
            default = 7;
            description = "How long a rotated audit log is kept.";
          };
        };
      };
      default = { };
      description = ''
        Recording what the API server was asked to do.

        Here rather than on the cluster, because every field of it is a flag
        and a mount for an API server *this floe* creates — a managed control
        plane logs through its provider, and a cluster this lab did not make
        has no server to pass flags to. The cluster module used to hold it
        and reach into this variant through a per-provisioner hook to inject
        it.
      '';
    };

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

    network = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Docker network the cluster's containers join.

        Filled in by placement, like `instanceName`: which network a cluster
        shares is a fact about what else is on the host, and a floe is
        instantiated before it is placed. Null for a cluster created outside
        a lab, where k3d makes its own.

        It was patched into the descriptor by the lab after the fact, through
        a per-provisioner hook keyed on `k3d` — which is the placement rule
        broken in code: the lab reached into one variant of a tagged union to
        set a field the floe had declared null.
      '';
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

    extraK3sArgs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            arg = lib.mkOption {
              type = lib.types.str;
              description = "The flag, as `k3s server` spells it.";
            };
            scope = lib.mkOption {
              type = lib.types.str;
              default = "server:*";
              description = "k3d's node selector — `server:*`, `agent:0`, and so on.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Flags handed to `k3s server` itself.

        Distinct from the apiserver args, which reach only kube-apiserver: a
        cluster whose datastore is not its own embedded etcd says so with
        `--datastore-endpoint`, and that is a k3s flag, not an apiserver one.

        Written last, after the disables and the CIDRs, so a lab that needs to
        override one of those can. k3s takes the last occurrence of a repeated
        flag.

        Nothing validates the contents. A flag k3s does not know fails when the
        node starts, which is the only place that can be known.
      '';
    };

    serviceSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.96.0.0/12";
      description = "Service CIDR. Same reasoning as `podSubnet`.";
    };
  };

  provides.cluster = sigs.KUBERNETES_CLUSTER;

  # Where this cluster is dialled. k3d's container naming is the only place
  # the answer exists, which is what makes it this floe's to give rather than
  # something the lab works out from a provisioner's name.
  provides.edge = sigs.CLUSTER_EDGE;

  # k3s ships local-path and this floe never turns it off, so a cluster k3d
  # established has somewhere for a PVC to bind. Said rather than assumed: a
  # stateful floe requires a `STORAGE_CLASS`, and a provisioner that ships none
  # — talos — provides none, so the same floe on that cluster is refused at the
  # hole rather than leaving a PVC Pending with nothing to say why.
  provides.storageClass = sigs.STORAGE_CLASS;

  # The CNI to start without flannel and apply instead, when the cluster this
  # establishes has one. Optional, and so wired only when a deployer names it:
  # a cluster that happens to contain cilium is not thereby a cluster whose
  # provisioner starts with no network, which is a third decision and is made
  # with `lab.defaults.CNI_BOOTSTRAP` or a `.bind`.
  #
  # Resolving it is what replaces a `disableFlannel` input and a hand-written
  # `autoDeployManifests` entry that had to agree with it. Both halves now come
  # from one place, so a cluster with no CNI at all and a cluster carrying two
  # are states nobody can write.
  optional.cniBootstrap = sigs.CNI_BOOTSTRAP;

  # The pull-through cache a node pulls images from, when the lab runs one.
  #
  # Declared here because k3d can mount a containerd config at creation —
  # which is the only reason a cluster can mirror at all. `talos-cluster`
  # declares no such hole: talosctl takes machine config rather than bind
  # mounts, so the file has no way to arrive. That was a lab turning the
  # registry off with `mkForce false` under a paragraph explaining why.
  #
  # Resolving it is what puts the state directory in the descriptor.
  # `create_cluster` used to join `service_state_dir(lab, "registry")` from a
  # literal and probe the filesystem for the files, so whether a cluster
  # mirrored was discovered at deploy rather than declared — a stale directory
  # mounted a mirror nobody asked for, and a skipped `registry-setup` silently
  # mounted none.
  optional.ociMirror = sigs.OCI_MIRROR;

  out.clusterDescriptor = kinds.cluster;
  out.steps = kinds.steps;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        cni = config.floe.requires.cniBootstrap;
        mirror = config.floe.requires.ociMirror;
      in
      {
        options.kubeContext = lib.mkOption {
          type = lib.types.str;
          description = "kubectl context name k3d writes for this cluster.";
        };

        options.edge = lib.mkOption {
          type = lib.types.attrs;
          description = "Where the lab's ingress dials this cluster's gateway.";
        };

        config.kubeContext = "k3d-${inputs.instanceName}";

        config.edge = {
          backend = "k3d-${inputs.instanceName}-server-0";

          httpPort = 80;
          httpsPort = 443;
        };

        config.floe.provides.edge = config.edge;

        config.floe.provides.storageClass = {
          className = "local-path";
          isDefault = true;
        };

        config.floe.provides.cluster = {
          inherit (inputs)
            name
            version
            podSubnet
            serviceSubnet
            ;
          context = config.kubeContext;

          assignsLoadBalancers = true;
        };

        config.floe.out.steps.create-cluster = {
          kind = "create-cluster";
          description = "Create k3d cluster '${inputs.name}'";
          providesCluster = "created";
          after = [ (needs planTokens.lab.network) ];

          params = {
            inherit (inputs) name;
            provisioner = "k3d";
          };
        };

        config.floe.out.clusterDescriptor = {
          inherit (inputs) name instanceName;
          kubeContext = config.kubeContext;
          inherit (inputs) wait;

          kubernetes = {
            distribution = "k3s";
            inherit (inputs) version;
            controlPlanes = 1;
            workers = 0;
          };

          network = {
            inherit (inputs) podSubnet serviceSubnet;
          };

          edge = {
            mode = "proxy";
          }
          // config.edge;

          config.k3d = {
            clusterName = inputs.instanceName;
            inherit (inputs) image;

            inherit (inputs) network;

            nodeConfigFrom = if mirror == null then null else mirror.name;

            noTraefik = true;
            noServiceLB = false;
            noLocalStorage = false;

            noFlannel = cni != null;

            ports = [ ];

            extraApiServerArgs = lib.optionals inputs.auditLogging.enable [
              "--audit-policy-file=/etc/rancher/k3s/audit-policy.yaml"
              "--audit-log-path=/var/log/kubernetes/audit.log"
              "--audit-log-maxage=${toString inputs.auditLogging.maxAgeDays}"
            ];

            extraVolumes = lib.optionals inputs.auditLogging.enable [
              {
                hostPath = "${auditPolicyFor inputs.auditLogging.level}";
                containerPath = "/etc/rancher/k3s/audit-policy.yaml";
              }
            ];
            autoDeployManifests =
              lib.optional (cni != null) {
                inherit (cni) name;
                path = cni.manifest;
              }
              ++ inputs.autoDeployManifests;

            inherit (inputs) extraK3sArgs;
          };
        };
      }
    )
  ];
}
