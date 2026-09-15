# Provisioning with bundles, running.
#
# Infrastructure can be brought into existence either way. A resource plans
# against recorded state and applies once; a bundle hands a controller a
# declaration and waits. `examples/labs/tests/cloud.nix` covers the resource
# route with providers that reach no network, and this covers the bundle
# route the same way: `provider-nop` reconciles to Ready and creates nothing.
#
# Crossplane is a bundle (RFC 0003 §2: it is a controller, it reconciles),
# which is what makes this lab the interesting half of that claim.
#
# What it proves is the lifecycle — Crossplane installing, a provider becoming
# healthy, its CRDs registering, a managed resource reaching Ready, and all of
# it coming apart on teardown. What it does not prove is the cross-cluster
# half: a nop resource emits only the connection details it was handed, so
# `sync-kubeconfig` and a second real cluster still need a real provider.
# `examples/labs/tests/provisions.nix` pins that ordering by rendering.
{
  lib,
  floes,
  config,
  ...
}:

let
in
{
  lab.name = lib.mkDefault "crossplane";
  lab.dns.zone = lib.mkDefault "crossplane.test";

  lab.registry.enable = lib.mkDefault true;

  # No ingress here: nothing in this lab is reached over HTTP, so there is
  # nothing for the endpoint probe to dial and it would be right to fail.
  lab.verify.endpoints.enable = lib.mkDefault false;

  lab.clusters.control.floes = {
    cluster = floes.k3d-cluster { };

    crossplane = floes.crossplane { };

    # Nothing here names crossplane. The provider requires a control plane and
    # the resource requires a provider, and the linker matches both — swapping
    # in a cloud provider is a one-line change to this block.
    provider = floes.crossplane-provider-nop { };

    workload = floes.nop-resource { };
  };
}
