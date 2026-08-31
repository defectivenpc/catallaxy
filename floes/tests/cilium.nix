# cilium, alone.
#
# The floe is in two halves that must agree, so most of this is about the
# agreement rather than about either half.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "cilium";
    inputs.chart = "/dev/null";
  };

  values = r.bundles.cilium.helmCharts.cilium.values;

  # The same function the bootstrap manifest is templated from. Reached
  # directly rather than through the floe, because the point of the file is
  # that both halves read it.
  mkValues = import ../cluster/cilium/values.nix { inherit lib; };
in
lib.runTests {

  # ---- the two halves agree --------------------------------------------

  # The release re-renders a DaemonSet on every `lab up`. If it differs from
  # the one k3s applied at startup, the agents restart and the cluster loses
  # its network in the middle of an apply — so the values are one file with
  # two readers, and this is what holds them to it.
  testTheReleaseRendersTheSameValuesAsTheBootstrap = {
    expr = values;
    expected = mkValues {
      k8sServiceHost = "localhost";
      k8sServicePort = "6443";
      hubble = false;
    };
  };

  # An input that reaches only one half is the same failure by another route:
  # a lab that turns Hubble on for the release and not the bootstrap gets two
  # different DaemonSets.
  testEveryValuesInputReachesTheRelease = {
    expr =
      (support.evalFloe {
        name = "cilium";
        inputs = {
          chart = "/dev/null";
          hubble = true;
          k8sServiceHost = "10.96.0.1";
          k8sServicePort = "443";
        };
      }).bundles.cilium.helmCharts.cilium.values;
    expected = mkValues {
      k8sServiceHost = "10.96.0.1";
      k8sServicePort = "443";
      hubble = true;
    };
  };

  # ---- what the values say ---------------------------------------------

  # k3s ships kube-proxy and cilium replaces it. Both running is not additive:
  # each writes its own datapath rules and they disagree about who owns a
  # Service's backends.
  testItReplacesKubeProxy = {
    expr = values.kubeProxyReplacement;
    expected = true;
  };

  # Cilium dials the apiserver before there is a network to dial it over, so
  # this cannot be a Service address — Services are what cilium implements.
  testItReachesTheApiserverWithoutAService = {
    expr = {
      inherit (values) k8sServiceHost k8sServicePort;
    };
    expected = {
      k8sServiceHost = "localhost";
      k8sServicePort = "6443";
    };
  };

  # The `gateway` floe implements Gateway API here. Two implementations of one
  # API is the conflict `provides` exists to refuse, and cilium's would add a
  # GatewayClass nobody asked for.
  testItDoesNotAlsoImplementGatewayApi = {
    expr = values ? gatewayAPI;
    expected = false;
  };

  testHubbleIsOffUnlessAsked = {
    expr = values.hubble.enabled;
    expected = false;
  };

  # ---- the release ------------------------------------------------------

  # No readiness probe at all, and that is the point. A DaemonSet has no
  # conditions, so `--for=condition=Ready daemonset/cilium` waits out its
  # whole timeout and then fails — which it did, on the first cluster that
  # booted on cilium, *after* cilium had already brought the nodes up.
  # `awaitRollout` asks the right question for a DaemonSet: every node has the
  # agent, not some quorum of them.
  testItLeavesReadinessToTheRollout = {
    expr = {
      probe = r.bundles.cilium.ready;
      rollout = r.bundles.cilium.awaitRollout;
    };
    expected = {
      probe = null;
      rollout = true;
    };
  };

  # kube-system is one the cluster ships with; emitting a Namespace for it has
  # the applier adopt something it did not create.
  testItCreatesNoNamespace = {
    expr = r.bundles.cilium.createNamespaces;
    expected = [ ];
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
