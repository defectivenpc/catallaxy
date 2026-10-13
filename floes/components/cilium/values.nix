# Cilium's chart values, in one place because two things render them.
#
# The CNI has to exist before any node can become Ready, and a floe's bundles
# are applied to a cluster that is already up — so cilium is templated once
# into the provisioner's auto-deploy directory (k3s applies it at startup) and
# installed again as an ordinary Helm release that takes ownership afterwards.
#
# Both must agree. Two spellings of these values means the deploy fights the
# bootstrap on every `lab up`: the release re-renders a DaemonSet that differs
# from the running one, the agents restart, and the cluster loses its network
# in the middle of an apply. That is why this is a file and not two literals.
{ lib }:

{
  # The apiserver cilium dials before there is a network to dial it over. It
  # cannot go through a Service, because Services are what cilium implements.
  k8sServiceHost,
  k8sServicePort,

  hubble ? false,
  kubeProxyReplacement ? true,
}:

{
  # k3s ships kube-proxy and cilium replaces it. Both running is not additive:
  # each writes its own datapath rules and the two disagree about who owns a
  # Service's backends.
  inherit kubeProxyReplacement k8sServiceHost k8sServicePort;

  ipam.mode = "kubernetes";
  operator.replicas = 1;

  # Off unless asked. The relay and UI are two more workloads and a
  # certificate cronJob, which is a lot to run by default on a lab whose point
  # is usually something else.
  hubble = {
    enabled = hubble;
  }
  // lib.optionalAttrs hubble {
    relay.enabled = true;
    ui.enabled = false;
    tls.auto.method = "cronJob";
  };

  # Deliberately absent: gatewayAPI, ingressController, bgpControlPlane,
  # l2announcements, egressGateway, encryption, clusterMesh, bandwidthManager.
  #
  # An earlier design carried an option for each, and the example labs set none
  # of them. Gateway API in particular is the `gateway` floe's job here — two
  # implementations of one API is the conflict `provides` exists to refuse,
  # and turning cilium's on would make a second GatewayClass nobody asked for.
}
