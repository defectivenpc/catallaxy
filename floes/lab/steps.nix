# Every plan step the lab's floes contribute, with their cluster conditions
# expanded.
#
# A collector: it answers no signature and installs nothing. Two collections,
# and the second is what makes the first useful — a floe states *when* it runs
# as a condition, because it has no name for a cluster it is not in, and
# turning `beforeClusters = "created"` into one anchor per cluster needs the
# cluster names. Those arrive as the keys of a `KUBERNETES_CLUSTER`
# collection: the three floes that provide it are all claims, and a claim's
# unit name is its cluster's.
#
# It was `modules/lab/steps.nix`, which read `catallaxy.labSteps` off the link
# and the names off `config.lab.clusters`. Both are collections now, so the
# fold is a unit of the thing it folds.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens wants clusterOfProvisionerUnit;
in
floe.mkFloe {
  name = "lab-steps";
  summary = "Folds every floe's plan steps into one set, expanding the cluster conditions.";

  # One set, so one of these. Two would each expand half the steps and the
  # plan would be assembled from whichever the container read first.
  singleton = true;

  collects = {
    step = sigs.LAB_STEPS;

    cluster = sigs.KUBERNETES_CLUSTER;
  };

  out.labSteps = kinds.labSteps;

  body =
    { collects, ... }:
    let
      clusterNames = map clusterOfProvisionerUnit (lib.attrNames collects.cluster);

      perCluster = token: map (n: wants (planTokens.cluster n).${token}) clusterNames;

      expand =
        step:
        builtins.removeAttrs step [
          "beforeClusters"
          "afterClusters"
        ]
        // lib.optionalAttrs (step ? beforeClusters) {
          before = (step.before or [ ]) ++ perCluster step.beforeClusters;
        }
        // lib.optionalAttrs (step ? afterClusters) {
          after = (step.after or [ ]) ++ perCluster step.afterClusters;
        };
    in
    {
      out.labSteps = lib.concatMapAttrs (
        _unit: contribution: lib.mapAttrs (_name: expand) contribution.steps
      ) collects.step;
    };
}
