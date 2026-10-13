# Evaluating one cluster, with no lab around it.
#
# A cluster denotes a claim and its content, and lowering is defined on closed
# compositions — so a cluster whose holes are all filled is a complete thing
# and needs nothing else to be one. `cata cluster up --from-file` already
# acts on one; this is the other half, writing one.
#
# The lowering reads exactly four things of a lab, and a standalone cluster
# answers each:
#
#   - its name, which defaults the instance name. A cluster on its own is its
#     own owner, so the instance name is the cluster's name.
#   - whether a lab fronts it, because Talos nodes have to be told what may
#     reach in. Nothing does.
#   - the link, because a cluster is a floe and something has to link it.
#     Here that is a link of the cluster and its claim.
#   - the delivery arrangement, folded from what the cluster said about
#     applying.
#
# The third is the interesting one. A link this small refuses an unfilled
# hole, which is the definition working rather than a limitation: a cluster
# with a hole nothing here fills is a *component*, and the thing that fills
# the rest is what a lab is. Two units and not one, because a cluster leaves
# its claim open and the claim is what answers it.
{
  lib,
  catallaxy,
  floes,
  catalogue,
}:

let
  inherit (import ./lower/cluster.nix { inherit lib catallaxy; })
    placeCluster
    lowerCluster
    ;
in
{
  # mkCluster :: { name; floe; claim; } -> lowered cluster
  #
  #   mkCluster ({ name = "standalone"; } // import ./examples/clusters/minimal.nix { … })
  #
  # The same two things a lab writes about a cluster — the floe it is and the
  # claim that answers it — and the same two phases over them. It was a
  # submodule whose only caller synthesised a whole `lab` record to evaluate
  # exactly one of it.
  mkCluster =
    {
      name,
      floe,
      claim,
    }:
    let
      placed = placeCluster {
        clusterName = name;
        labName = name;
        inherit floe claim;
      };

      link = catallaxy.floe.link {
        units = {
          ${name} = placed.clusterFloe;
          ${catallaxy.claimUnitFor name} = placed.claim;

          delivery = floes.lab-delivery { };
        };
        inherit catalogue;
      };

      lowered = lowerCluster {
        clusterName = name;
        inherit placed;

        lab = {
          inherit name link;
          hasIngress = false;
          cdArrangement = catallaxy.cdArrangementOf link;
        };
      };

      failed = builtins.filter (a: !a.assertion) lowered.assertions;
    in
    lib.throwIf (failed != [ ]) (
      "cluster '${name}' has failed assertions:\n"
      + lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed
    ) (placed // lowered);
}
