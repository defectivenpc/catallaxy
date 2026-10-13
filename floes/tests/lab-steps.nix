# lab-steps, alone.
#
# The fold is trivial; the expansion is not, and it is the whole reason this
# floe exists. A floe states *when* it runs as a condition because it has no
# name for a cluster it is not in, and turning that condition into anchors
# needs the cluster names — which arrive as the keys of a collection, not as
# something the container hands in.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  stepsWith =
    without:
    (support.evalFloe {
      name = "lab-steps";
      inherit without;
    }).link.out."catallaxy.labSteps".lab-steps;
in
lib.runTests {

  # The contribution arrives keyed by step name, with the condition replaced by
  # one `wants` anchor per cluster. `wants` and not `needs`: the anchor has to
  # be allowed to match nothing, which is what makes the no-clusters case below
  # an unconstrained step rather than an unsatisfiable one.
  #
  # One cluster here, because the stub is one claim. The multi-cluster shape is
  # pinned where the clusters are, in the plan snapshots.
  testItExpandsAConditionIntoOneAnchorPerCluster = {
    expr = (stepsWith [ ]).stub-step;
    expected = {
      kind = "run-script";
      description = "Stub contributed step";
      before = [ "optional:provides:cluster/stub-cluster/created" ];
    };
  };

  # The name in the anchor is the *collection's key* with `-claim` stripped,
  # which is how a floe gets at cluster names it cannot be told. The harness
  # names its provider `stub-cluster` rather than `<x>-claim`, so what this
  # pins is that the key is what is used; the stripping itself is exercised by
  # every plan snapshot, where the claims are real.
  testTheNameInTheAnchorIsTheCollectionsKey = {
    expr = lib.any (a: lib.hasInfix "cluster/stub-cluster/" a) (stepsWith [ ]).stub-step.before;
    expected = true;
  };

  # A lab with no clusters expands the condition to nothing, leaving the step
  # with no anchor from it. That is the right answer — there is nothing to be
  # before — and it is why both conditions are `wants`.
  testALabWithNoClustersExpandsToNothing = {
    expr = (stepsWith [ "cluster" ]).stub-step.before;
    expected = [ ];
  };

  # The condition itself never reaches the plan: it is vocabulary for a floe,
  # and the planner only knows anchors.
  testTheConditionDoesNotSurviveTheFold = {
    expr = (stepsWith [ ]).stub-step ? beforeClusters;
    expected = false;
  };

  # One fold, so one of these. Two would each expand half the steps and the
  # plan would be assembled from whichever the container read first.
  testThereIsOnlyEverOneFold = {
    expr =
      (support.evalFloe {
        name = "lab-steps";
        without = [ ];
      }).link.floeNames.lab-steps != null;
    expected = true;
  };
}
