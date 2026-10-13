# k3d-cluster, alone.
#
# The floe every lab has one of, and the only one that emits
# `catallaxy.cluster` rather than a component. What is worth pinning is the
# seam it sits on: two names that must not be confused, one context computed
# once, and the fields it deliberately leaves for the lab to fill.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

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
  # cluster namespace, and they are chosen rather than discovered.
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

  # Starting with no CNI is resolved, not written. It used to be a
  # `disableFlannel` input a lab set alongside an `autoDeployManifests` entry
  # that had to agree with it, because the link graph had no direction from a
  # component to the thing that establishes its cluster. A claim is a unit
  # beside its cluster now, so there is one — the cluster exports what its CNI
  # floe provides and this resolves it.
  testTheCniIsResolvedNotWritten = {
    expr = lib.attrNames r.def.optional;
    expected = [
      "cniBootstrap"
      "ociMirror"
    ];
  };

  # And the input is gone, so the two halves cannot disagree: a lab can no
  # longer ask for no flannel without saying what replaces it.
  testNoFlannelCannotBeAskedForAlone = {
    expr = r.def.inputs ? disableFlannel;
    expected = false;
  };

  # Nothing resolved means the provisioner keeps its own network. An optional
  # hole is never wired by a provider merely being present, so a cluster that
  # happens to contain cilium is not thereby a cluster with no CNI at boot.
  testWithoutACniItKeepsFlannel =
    let
      plain = support.evalFloe {
        name = "k3d-cluster";
        inputs = {
          name = "app";
          instanceName = "app";
        };
      };
    in
    {
      expr = plain.link.out."catallaxy.cluster".k3d-cluster.config.k3d.noFlannel;
      expected = false;
    };

  # Whether a node pulls through the lab's cache is resolved, and resolving it
  # is what puts the state directory in the descriptor. `create_cluster` used
  # to join `service_state_dir(lab, "registry")` from a literal and probe the
  # filesystem for the file — so a stale directory mounted a mirror nobody
  # asked for, and a cluster whose `registry-setup` had not run mounted none
  # and said nothing.
  #
  # This floe declares the hole because k3d can mount a containerd config at
  # creation. `talos-cluster` cannot, declares none, and that is the whole of
  # why a Talos lab does not mirror.
  testTheMirrorIsNamedNotGuessed = {
    expr =
      let
        unmirrored = support.evalFloe {
          name = "k3d-cluster";
          inputs = {
            name = "app";
            instanceName = "app";
          };
          without = [ "ociMirror" ];
        };
      in
      {
        resolved = descriptor.config.k3d.nodeConfigFrom;
        unresolved = unmirrored.link.out."catallaxy.cluster".k3d-cluster.config.k3d.nodeConfigFrom;
      };
    expected = {
      resolved = "stub-ociMirror";
      unresolved = null;
    };
  };

  # The lab is a k3d cluster's edge, and the floe says so rather than the lab
  # inferring it. `modules/lab/cluster/default.nix` used to test
  # `provisioner == "k3d"` and build this container name itself, which made
  # every new provisioner an edit to the lab — the one thing adding one must
  # not be.
  testItNamesTheLabAsItsEdge = {
    expr = descriptor.edge;
    expected = {
      mode = "proxy";
      backend = "k3d-homelab-local-app-server-0";

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
      provisioner = lib.head (lib.attrNames descriptor.config);
      inherit (descriptor.kubernetes) distribution controlPlanes workers;
    };
    expected = {
      provisioner = "k3d";
      distribution = "k3s";
      controlPlanes = 1;
      workers = 0;
    };
  };
}
