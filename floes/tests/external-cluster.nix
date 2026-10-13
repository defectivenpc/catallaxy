# external-cluster, alone.
#
# The third provisioner, and the one that carries no provisioner config worth
# the name. What is worth pinning is that it still answers everything a member
# reads — a cluster this lab did not create is not a cluster its members know
# less about.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  r = support.evalFloe {
    name = "external-cluster";
    inputs = {
      name = "workload";
      context = "cata-demo-workload";
      madeBy = "crossplane on 'mgmt'";
      podSubnet = "10.244.0.0/16";
      serviceSubnet = "10.245.0.0/16";
    };
  };

  descriptor = r.link.out."catallaxy.cluster".external-cluster;
in
lib.runTests {

  # Every field of `KUBERNETES_CLUSTER` is still concrete.
  # This is the case that could have broken the rule and does not: the
  # cluster's *endpoint* is a discovery, and nothing here exposes it, because
  # an endpoint reaches kubectl through a kubeconfig and never reaches a
  # manifest.
  testEveryClusterFactIsStillADecision = {
    expr = r.provides.cluster;
    expected = {
      name = "workload";
      version = "1.31";
      context = "cata-demo-workload";
      podSubnet = "10.244.0.0/16";
      serviceSubnet = "10.245.0.0/16";
      assignsLoadBalancers = true;
    };
  };

  # The context is a name catallaxy chooses, not one the producing tool hands
  # back. `cata` writes the fetched kubeconfig under it — which is the whole
  # reason a cluster made somewhere else can still have a concrete context.
  testTheContextIsChosenRatherThanDiscovered = {
    expr = descriptor.kubeContext;
    expected = "cata-demo-workload";
  };

  # The variant's own key says it. `lib/lower/plan.nix` reads that to decide
  # whether the cluster joins the lab's network, so a lab of nothing but these
  # creates no docker network at all — and there is no `provider` string beside
  # the block to disagree with it.
  testItIsNotOnTheLabsDockerNetwork = {
    expr = lib.attrNames descriptor.config;
    expected = [ "external" ];
  };

  # `self`, never `proxy`: the lab's proxy reaches backends on its own docker
  # network and this cluster is not on it. it calls that a refusal
  # to route rather than a deferred address.
  testTheLabIsNotItsEdge = {
    expr = descriptor.edge;
    expected = {
      mode = "self";
      backend = null;
      httpPort = 80;
      httpsPort = 443;
    };
  };

  # What made it, for the operator reading a plan. The harness wires every
  # stub, so the optional `CLUSTER_PROVISIONING` hole is filled here and
  # `madeBy` is the object's coordinates — which is also what the planner
  # waits on, so the text an operator reads and the thing being waited for
  # cannot drift. A cluster nothing in the lab creates says so in free text
  # instead, through the input of the same name.
  #
  # `kubeconfigFrom` is null here: this fixture is the bundle case, where the
  # kubeconfig is in a connection Secret and the lab reaches it through the
  # cluster that reconciles the object. The lab strips the field before the
  # descriptor becomes a `ClusterSpec` — it derives a step from it and the
  # step carries the address, so passing it on would be the same fact in the
  # document twice.
  testItSaysWhatMakesIt = {
    expr = descriptor.config;
    expected = {
      external = {
        madeBy = "clusters.example.com/stub-workload";
        provisionedBy = {
          resourceKind = "clusters.example.com";
          resourceName = "stub-workload";
        };
        kubeconfigFrom = null;
      };
    };
  };

  # And the other way: a cluster nothing here creates leaves the hole empty
  # and says so in words.
  testAClusterNobodyHereMakesSaysSoInWords = {
    expr =
      ((support.evalFloe {
        name = "external-cluster";
        inputs = {
          name = "demo";
          context = "cata-demo-workload";
          madeBy = "a hand, once, in 2019";
          podSubnet = "10.246.0.0/16";
          serviceSubnet = "10.113.0.0/16";
        };
        without = [ "provisioning" ];
      }).link.out."catallaxy.cluster".external-cluster
      ).config.external.madeBy;
    expected = "a hand, once, in 2019";
  };

  # Zero rather than one. Whoever made it decided the shape; a record claiming
  # one control plane would report drift against every cluster that has three.
  testItClaimsNoNodeCountItCannotKnow = {
    expr = {
      inherit (descriptor.kubernetes) controlPlanes workers;
    };
    expected = {
      controlPlanes = 0;
      workers = 0;
    };
  };
}
