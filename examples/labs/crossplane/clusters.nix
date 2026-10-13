# The cluster `crossplane` stands up, as a floe.
#
# One hole and nothing else: this lab proves that a managed resource can be
# reconciled, so it has no gateway, no issuer and no zone — and declaring no
# `DNS_ZONE` hole is how that is said. A cluster that needed one and forgot to
# declare it is refused by the linker naming the signature, not by a route
# that resolves to nothing.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  control = mkClusterFloe {
    name = "crossplane-control";
    summary = "A Crossplane control plane, one provider, and one resource it reconciles.";

    requires.claim = sigs.KUBERNETES_CLUSTER;

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "kapp/delivery";

    units = _: {
      kapp = floes.kapp { };

      crossplane = floes.crossplane { };
      provider = floes.crossplane-provider-nop { };
      workload = floes.nop-resource { };
    };
  };
}
