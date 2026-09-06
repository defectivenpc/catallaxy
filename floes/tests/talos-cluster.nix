# talos-cluster, alone.
#
# The second provisioner. What is worth pinning here is not that it works but
# that it differs from k3d in exactly the ways a provisioner is allowed to,
# and in no others: the same signature, the same kind, a different variant of
# the config union, and three facts a member reads instead of inferring.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  r = support.evalFloe {
    name = "talos-cluster";
    inputs = {
      name = "app";
      instanceName = "minimal-talos-app";
    };
  };

  descriptor = r.link.out."catallaxy.cluster".talos-cluster;

  kinds = (import ../../lib/floe-catallaxy { inherit lib pkgs; }).kinds;
in
lib.runTests {

  # The same split k3d makes, for the same reason: `name` is what members and
  # the kubeconfig see, `instanceName` is what talosctl calls the containers.
  testTheTwoNamesStaySeparate = {
    expr = {
      signature = r.provides.cluster.name;
      containers = descriptor.config.talos.clusterName;
      descriptor = descriptor.name;
    };
    expected = {
      signature = "app";
      containers = "minimal-talos-app";
      descriptor = "app";
    };
  };

  # What talosctl actually writes into the kubeconfig. The generic
  # `<prefix>-<cluster>` shape matches nothing it produces, and every step
  # after cluster creation addresses the cluster through this string — so
  # getting it wrong is a lab that creates a cluster and then cannot reach it.
  testTheContextIsWhatTalosctlWrites = {
    expr = r.provides.cluster.context;
    expected = "admin@minimal-talos-app";
  };

  # The fact the gateway reads. Nothing here ships a ServiceLB, so a
  # LoadBalancer Service stays Pending forever while the node's 80 answers
  # nothing — and neither is an error anything reports.
  #
  # This is the field that replaced the previous implementation's
  # `provisionerOut.publishesGatewayPorts`, which the gateway derived by
  # asking which provisioner it was on. A floe asking "am I on k3d" needs
  # editing for every provisioner; one asking "does a LoadBalancer get an
  # address here" is asking what it depends on.
  testNothingAssignsLoadBalancerAddresses = {
    expr = r.provides.cluster.assignsLoadBalancers;
    expected = false;
  };

  # And so the lab dials a NodePort. Read from the distribution rather than
  # written here, because the gateway binds the same numbers from inside a
  # cluster it requires and cannot read them off this floe — a floe cannot
  # require the thing that requires it.
  testTheLabReachesItOnTheGatewayNodePorts = {
    expr = descriptor.edge;
    expected = {
      mode = "proxy";
      backend = "minimal-talos-app-controlplane-1";
      httpPort = kinds.gatewayNodePorts.http;
      httpsPort = kinds.gatewayNodePorts.https;
    };
  };

  # talosctl will not join a network it did not make, and kube-proxy in
  # nftables mode will not answer a NodePort on an interface added afterwards
  # — so the lab reaches *into* this cluster's network rather than the
  # cluster joining the lab's. Which containers do that is a lab fact, left
  # empty here exactly as k3d leaves `network` null.
  testItLeavesWhoReachesInToTheLab = {
    expr = descriptor.config.talos.reachableFrom;
    expected = [ ];
  };

  # A control plane keeps the standard NoSchedule taint, unlike a k3d server
  # node, so a cluster with no workers has nowhere to run a workload. The
  # symptom is every Pod Pending rather than anything naming the taint.
  testItDefaultsToAWorkerBecauseTheControlPlaneIsTainted = {
    expr = descriptor.kubernetes.workers;
    expected = 1;
  };

  # Two versions that are not the same string and are not interchangeable:
  # one is the schema set manifests are typed against, the other is an image
  # tag. Conflating them produces either a version nothing validates against
  # or a tag nothing can pull.
  testTheSchemaVersionAndTheKubeletTagAreDistinct = {
    expr = {
      schema = descriptor.kubernetes.version;
      tag = descriptor.config.talos.kubernetesVersion;
    };
    expected = {
      schema = "1.31";
      tag = "1.31.4";
    };
  };

  # The union's key is the provisioner, and this is the second variant to
  # prove the first was not a special case. A `k3d` key here would be a
  # cluster claiming to be built by something it is not.
  testItEmitsTheTalosVariantAndOnlyThat = {
    expr = lib.attrNames descriptor.config;
    expected = [ "talos" ];
  };
}
