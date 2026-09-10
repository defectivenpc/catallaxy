# k3d-cluster, alone.
#
# The floe every lab has one of, and the only one that emits
# `catallaxy.cluster` rather than a component. What is worth pinning is the
# seam it sits on: two names that must not be confused, one context computed
# once, and the fields it deliberately leaves for the lab to fill.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  r = support.evalFloe {
    name = "k3d-cluster";
    inputs = {
      name = "app";
      instanceName = "homelab-local-app";
    };
  };

  descriptor = r.link.out."catallaxy.cluster".k3d-cluster;
in
lib.runTests {

  # `name` is what members and the kubeconfig see; `instanceName` is what k3d
  # calls the containers. Two labs may each hold a cluster called `app` on one
  # docker host, so collapsing these into one is a collision that only shows
  # up when someone stands the second lab up.
  testTheTwoNamesStaySeparate = {
    expr = {
      signature = r.provides.cluster.name;
      containers = descriptor.config.k3d.clusterName;
      descriptor = descriptor.name;
    };
    expected = {
      signature = "app";
      containers = "homelab-local-app";
      descriptor = "app";
    };
  };

  # One assembly point, two projections. A member reads the context off the
  # signature and the CLI reads it off the descriptor, and they are the same
  # string because they are the same expression — deriving it twice is what
  # the projection rule forbids.
  testTheContextIsComputedOnceAndProjectedTwice = {
    expr = r.provides.cluster.context == descriptor.kubeContext;
    expected = true;
  };

  testTheContextIsBuiltFromWhatK3dActuallyNames = {
    expr = descriptor.kubeContext;
    expected = "k3d-homelab-local-app";
  };

  # The ranges reach members through the signature rather than an ambient
  # cluster namespace, and they are chosen rather than discovered (RFC 0005
  # §6.3).
  testMembersReadTheRangesThroughTheSignature = {
    expr = {
      inherit (r.provides.cluster) podSubnet serviceSubnet version;
    };
    expected = {
      podSubnet = "10.244.0.0/16";
      serviceSubnet = "10.96.0.0/12";
      version = "1.31";
    };
  };

  # Which docker network the cluster joins is a lab fact — the cluster does
  # not know what else shares it. Null here, filled by the lab; a default
  # invented at this level would be one the lab then has to override.
  testItLeavesTheDockerNetworkToTheLab = {
    expr = descriptor.config.k3d.network;
    expected = null;
  };

  # Traefik comes from the gateway floe at a version the lab pins, so k3s's
  # own would be a second ingress nobody declared. The rest of k3s's batteries
  # stay in: a floe needing Cilium or OpenEBS turns the conflicting one off.
  testItDropsOnlyTheIngressAFloeReplaces = {
    expr = {
      inherit (descriptor.config.k3d)
        noTraefik
        noServiceLB
        noLocalStorage
        noFlannel
        ;
    };
    expected = {
      noTraefik = true;
      noServiceLB = false;
      noLocalStorage = false;
      noFlannel = false;
    };
  };

  # Starting with no CNI is the lab's call, and it travels as an input rather
  # than as a writeback from whichever floe provides the network — the link
  # graph has no direction for that, and it is what kept cilium unmigrated.
  testTheCniIsAnInputNotAWriteback =
    let
      cilium = support.evalFloe {
        name = "k3d-cluster";
        inputs = {
          name = "app";
          instanceName = "app";
          disableFlannel = true;
        };
      };
    in
    {
      expr = cilium.link.out."catallaxy.cluster".k3d-cluster.config.k3d.noFlannel;
      expected = true;
    };

  # The lab is a k3d cluster's edge, and the floe says so rather than the lab
  # inferring it. `modules/lab/cluster.nix` used to test `provisioner == "k3d"`
  # and build this container name itself, which made every new provisioner an
  # edit to the lab — the one thing RFC 0005 §8.2 says adding one must not be.
  testItNamesTheLabAsItsEdge = {
    expr = descriptor.edge;
    expected = {
      mode = "proxy";
      # The instance name, not the cluster name: two labs each holding a
      # cluster called `app` have distinct containers and so distinct edges.
      backend = "k3d-homelab-local-app-server-0";

      # k3s's ServiceLB binds these on the node. A provisioner without one
      # answers a NodePort here instead, which is the whole reason the ports
      # are the provisioner's to say rather than the lab's to assume.
      httpPort = 80;
      httpsPort = 443;
    };
  };

  # Pinned, not floating. A lab is reproducible or it is not.
  testTheNodeImageIsPinned = {
    expr = lib.hasInfix ":v" descriptor.config.k3d.image;
    expected = true;
  };

  testItProvisionsItselfOnDocker = {
    expr = {
      # The provisioner is the union's key. There is no separate field
      # to read, which is the point: a tag beside an untagged block is two
      # facts that can disagree.
      provisioner = lib.head (lib.attrNames descriptor.config);
      inherit (descriptor) provider;
      inherit (descriptor.kubernetes) distribution controlPlanes workers;
    };
    expected = {
      provisioner = "k3d";
      provider = "docker";
      distribution = "k3s";
      controlPlanes = 1;
      workers = 0;
    };
  };
}
