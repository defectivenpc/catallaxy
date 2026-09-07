# One cluster bringing another into existence.
#
# `mgmt` is an ordinary k3d cluster the operator's machine creates. `workload`
# is a cluster something in `mgmt` reconciles into being — modelled here as a
# Crossplane CR, though nothing in this fixture is provider-specific.
#
# What it pins is the *order*, which is RFC 0005 §7 open question 1 answered.
# The previous implementation left the edge out of the apply order and its
# plan opened by "creating" both cloud clusters before the management cluster
# existed; it ran only because those steps are no-ops. The deploy plan here
# should read:
#
#   create mgmt -> deploy mgmt -> reconcile workload -> sync its kubeconfig
#     -> create workload (a no-op) -> deploy workload
#
# and the teardown should reverse it, with the cloud resources released while
# the cluster is still there to release them.
#
# It renders and is checked like any lab and never enters the e2e set: it
# needs a Crossplane provider with a cloud account behind it. What has no
# runtime symptom short of that — the order — is exactly what this covers.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  ...
}:

{
  lab.name = "provisions";
  lab.dns.zone = "provisions.test";
  lab.network.subnet = "172.42.0.0/16";
  lab.egress.port = 3139;
  lab.dns.hostPort = 5372;

  lab.clusters.mgmt.floes = {
    cluster = floes.k3d-cluster {
      name = "mgmt";
      instanceName = "provisions-mgmt";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    gateway = floes.gateway { chart = "${cataCharts.traefik.chart}"; };
  };

  # Declared on the management cluster, and nowhere else. A cluster naming
  # what creates it would be a container's provisions depending on its
  # contents, which RFC 0005 §6.2 forbids.
  lab.clusters.mgmt.provisions.workload = {
    resourceKind = "clusters.kubernetes.digitalocean.crossplane.io";
  };

  lab.clusters.workload.floes = {
    cluster = floes.external-cluster {
      name = "workload";
      # A name catallaxy chooses. `cata` writes the fetched kubeconfig under
      # it, which is what keeps the context concrete for a cluster whose
      # endpoint is not.
      context = "cata-provisions-workload";
      madeBy = "crossplane on 'mgmt'";

      # Distinct from `mgmt`'s, and declared rather than defaulted: for a
      # cluster this lab does not create, a default would be a guess about
      # somebody else's network that every member then renders against.
      podSubnet = "10.246.0.0/16";
      serviceSubnet = "10.113.0.0/16";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    gateway = floes.gateway { chart = "${cataCharts.traefik.chart}"; };
    podinfo = floes.podinfo { };
  };
}
