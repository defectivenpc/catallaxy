# The reconcile camp, running.
#
# Catallaxy provisions through two camps. The state-based one plans against
# recorded state and applies once; the reconcile one hands a controller a
# declaration and waits. `examples/labs/tests/cloud.nix` covers the first with
# providers that reach no network, and this covers the second the same way:
# `provider-nop` reconciles a resource to Ready and creates nothing.
#
# What it proves is the lifecycle — Crossplane installing, a provider becoming
# healthy, its CRDs registering, a managed resource reaching Ready, and all of
# it coming apart on teardown. What it does not prove is the cross-cluster
# half: a nop resource emits only the connection details it was handed, so
# `sync-kubeconfig` and a second real cluster still need a real provider.
# `examples/labs/tests/provisions.nix` pins that ordering by rendering.
{
  lib,
  cataCharts,
  floes,
  config,
  ...
}:

let
  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";
in
{
  lab.name = lib.mkDefault "crossplane";
  lab.dns.zone = lib.mkDefault "crossplane.test";

  lab.registry.enable = lib.mkDefault true;

  # No ingress here: nothing in this lab is reached over HTTP, so there is
  # nothing for the endpoint probe to dial and it would be right to fail.
  lab.verify.endpoints.enable = lib.mkDefault false;

  lab.clusters.control.floes = {
    cluster = floes.k3d-cluster {
      name = "control";
      instanceName = instanceOf "control";
    };

    crossplane = floes.crossplane {
      chart = "${cataCharts.crossplane.chart}";
      crds = "${cataCharts.crossplane.crds}";
    };

    # Nothing here names crossplane. The provider requires a control plane and
    # the resource requires a provider, and the linker matches both — swapping
    # in a cloud provider is a one-line change to this block.
    provider = floes.crossplane-provider-nop { };

    workload = floes.nop-resource { };
  };
}
