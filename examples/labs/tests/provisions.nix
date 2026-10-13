# One cluster provisioning another, which is one of the three features that
# turned out to be a parent filling a hole.
#
# `mgmt` runs the control plane and exports `CLUSTER_PROVISIONING`; the
# `workload` cluster's claim is an `external-cluster`, because nothing here
# creates it — what creates it is a managed resource in `mgmt`, and the claim
# is a retrieval rather than a recipe.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters/provisions.nix { inherit catallaxy floes lib; };
in
catallaxy.mkLabFloe
  {
    name = "provisions";
    summary = "One cluster provisioning another.";

    clusters = _: {
      mgmt = {
        floe = clusters.mgmt { };
        claim = floes.k3d-cluster { };
      };

      workload = {
        floe = clusters.workload { };
        claim = floes.external-cluster {
          context = "cata-provisions-workload";
          podSubnet = "10.246.0.0/16";
          serviceSubnet = "10.113.0.0/16";
        };
      };
    };
  }
  {
    name = "provisions";
    zone = "provisions.test";

    # Which cluster an optional hole means. Holding a cluster that provisions
    # others is not the same statement as wanting this one provisioned by it.
    defaults.CLUSTER_PROVISIONING = "mgmt";
  }
