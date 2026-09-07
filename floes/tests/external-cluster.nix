# external-cluster, alone.
#
# The third provisioner, and the one that carries no provisioner config worth
# the name. What is worth pinning is that it still answers everything a member
# reads — a cluster this lab did not create is not a cluster its members know
# less about.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

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

  # Every field of `KUBERNETES_CLUSTER` is still concrete — RFC 0005 §6.3.
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

  # Not `docker`. `modules/lab/plan.nix` reads this to decide whether the
  # cluster joins the lab's network, so a lab of nothing but these creates no
  # docker network at all.
  testItIsNotOnTheLabsDockerNetwork = {
    expr = descriptor.provider;
    expected = "external";
  };

  # `self`, never `proxy`: the lab's proxy reaches backends on its own docker
  # network and this cluster is not on it. RFC 0005 §6.4 calls that a refusal
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

  # Free text, carried for the operator reading a plan, and never dispatched
  # on — dispatching would make it a provisioner enum again.
  #
  # `kubeconfigFrom` is null here: this fixture is the reconcile-camp case,
  # where the kubeconfig is in a connection Secret and the lab reaches it
  # through the management cluster's `provisions`. The lab strips this field
  # before the descriptor becomes a `ClusterSpec` — it derives a step from it
  # and the step carries the address, so passing it on would be the same fact
  # in the document twice.
  testItSaysWhatMakesItWithoutTheLabActingOnThat = {
    expr = descriptor.config;
    expected = {
      external = {
        madeBy = "crossplane on 'mgmt'";
        kubeconfigFrom = null;
      };
    };
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
