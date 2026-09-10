# doks, alone.
#
# The first floe that names a real provider. What is worth pinning is that it
# is an ordinary member of the resources camp — same `mkFloe`, same
# `requires.cluster`, same output kinds as the fixture `provisioned` floe —
# and that the two things a cloud cluster could have got wrong, it does not:
# it pins a version rather than a prefix, and it declares the outputs it will
# be checked against.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  r = support.evalFloe {
    name = "doks";
    inputs = {
      name = "workload";
      version = "1.31.1-do.4";
    };
  };

  published = support.evalFloe {
    name = "doks";
    inputs = {
      name = "workload";
      version = "1.31.1-do.4";
      publishKubeconfigTo = {
        store = "runtime";
        key = "clusters/workload/kubeconfig";
      };
    };
  };

  resource = r.link.out."catallaxy.resources".doks.cluster;
in
lib.runTests {

  # Before any cluster exists — the case RFC 0003 §2 says the reconcile camp
  # cannot cover at all, because there is no reconciler yet to reconcile it.
  testAClusterIsMadeBeforeAnyClusterExists = {
    expr = resource.phase;
    expected = "before-clusters";
  };

  # The registry's vocabulary, not a tool's. RFC 0003 §12.10: nothing in a
  # floe names Terraform, OpenTofu or Pulumi.
  testItNamesAProviderAndNotATool = {
    expr = "${resource.provider}.${resource.type}";
    expected = "digitalocean.digitalocean_kubernetes_cluster";
  };

  # The provider accepts a prefix like `1.31.` and resolves it to whatever is
  # current, so a lab that wrote one would get a different cluster on
  # different days and call it reproducible. Required, and required to be
  # whole.
  testTheVersionIsAWholeSlugAndNotAPrefix = {
    expr = resource.inputs.version;
    expected = "1.31.1-do.4";
  };

  # Declared, never inferred (RFC 0003 §3). `kube_config` is what the
  # publication reads; the two subnets are read back so the apply can be
  # checked against what the lab decided rather than sampled.
  testItDeclaresTheOutputsItWillBeCheckedAgainst = {
    expr = resource.outputs;
    expected = [
      "id"
      "endpoint"
      "kube_config"
      "cluster_subnet"
      "service_subnet"
    ];
  };

  # A default pool, named after the cluster so two labs' pools are two names.
  testItAsksForANodePool = {
    expr = resource.inputs.node_pool;
    expected = {
      name = "workload-default";
      size = "s-2vcpu-2gb";
      node_count = 2;
    };
  };

  # Off unless the lab asks. A kubeconfig that stays in state is a complete
  # arrangement for a cluster nothing else has to reach.
  testTheKubeconfigIsNotPublishedUntilTheLabAsks = {
    expr = r.link.out."catallaxy.publications".doks or { };
    expected = { };
  };

  # And when it is, it goes into a store the lab already declares — no second
  # addressing scheme, which RFC 0003 §7 warns is the easy thing to get wrong.
  testAPublishedKubeconfigLandsInAnOrdinaryStore = {
    expr = published.link.out."catallaxy.publications".doks.kubeconfig;
    expected = {
      resource = "cluster";
      output = "kube_config";
      store = "runtime";
      key = "clusters/workload/kubeconfig";
    };
  };

  # It provides no cluster. The cluster it creates is a separate
  # `lab.clusters` entry, because the thing that declares a cluster into
  # existence and the cluster itself are two nodes — collapsing them would
  # make a cluster a member of itself.
  testItDoesNotProvideTheClusterItCreates = {
    expr = lib.attrNames r.provides;
    expected = [ ];
  };
}
