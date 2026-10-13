# Two clusters for `self-edge`, where the lab fronts one and not the other.
#
# Identical but for their address plan, which is a decision written down
# rather than derived from a name — a rename would otherwise silently move a
# running cluster's subnet.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  # `fronted` decides whether this cluster exports its exposure, and that is
  # the whole of saying who reaches it. A lab has nothing to answer for a
  # cluster that is its own edge, so the boundary stays shut — rather than
  # carrying a mode for the resolver to filter on. ADR 0004.
  mk =
    { name, fronted }:
    mkClusterFloe {
      name = "self-edge-${name}";
      summary = "A gateway and one routed workload, for proving who fronts a cluster.";

      requires = {
        claim = sigs.KUBERNETES_CLUSTER;
        zone = sigs.DNS_ZONE;
      };

      # Only the fronted one. An injected value nothing inside reads is
      # refused, and nothing inside an unfronted cluster reads an address the
      # lab is not going to dial — so this is the same decision as the export,
      # said once.
      optional = {
        # The lab's root, so the issuer in here signs from it rather than
        # minting a second over the Secret `cata lab up` seeded. Both
        # clusters, fronted or not: being its own edge is about routing, not
        # about which chain its certificates come from.
        labCa = sigs.LAB_CA;
      }
      // lib.optionalAttrs fronted { edge = sigs.CLUSTER_EDGE; };

      provides = {
        delivery = sigs.DELIVERY_POLICY;
      }
      // lib.optionalAttrs fronted { exposure = sigs.HOST_EXPOSURE; };

      exports = {
        delivery = "kapp/delivery";
      }
      // lib.optionalAttrs fronted { exposure = "gateway/exposure"; };

      units = _: {
        kapp = floes.kapp { };
        gateway-api = floes.gateway-api-crds { };
        cert-manager = floes.cert-manager { };
        gateway = floes.gateway { };
        podinfo = floes.podinfo { };
      };
    };
}
