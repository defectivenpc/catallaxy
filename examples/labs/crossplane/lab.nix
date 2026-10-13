# Crossplane reconciling one resource, and nothing else.
#
# The narrowest lab in the tree: no ingress, no resolver, no issuer. It exists
# so the managed-resource path — a control plane, a provider, a claim that
# becomes a real object — is exercised without anything else in the way.
#
# It declares no inputs of its own, because its one environment varies nothing:
# `crossplane.nop` is this lab under the name it is allocated from.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters.nix { inherit catallaxy floes lib; };
in
catallaxy.mkLabFloe {
  name = "crossplane";
  summary = "Crossplane reconciling one resource, and nothing else.";

  inputs = {
    zone.default = "crossplane.test";

    # Nothing is routed, so there is nothing to probe.
    verifyEndpoints.default.enable = false;
  };

  units = _: {
    registry = floes.lab-registry { };
  };

  clusters = _: {
    control = {
      floe = clusters.control { };
      claim = floes.k3d-cluster { };
    };
  };
}
