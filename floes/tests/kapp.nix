# kapp, alone.
#
# It renders nothing, so there are no bundles to assert on and the whole of
# what it says is the answer it gives: this cluster is applied by `cata`, with
# nothing to bootstrap first. What makes that worth a floe rather than a
# default is that absence now means absence.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe { name = "kapp"; };
in
lib.runTests {

  testItAnswersWithKappAppliedServerSide = {
    expr = r.provides.delivery;
    expected = {
      strategy = "kapp";
      bootstrapTool = "kubectl-ssa";

      context = "k3d-stub";
      waitTimeout = "10m";
    };
  };

  # The apply's wait is the deployer's, on the thing that applies.
  testTheWaitIsAnInput = {
    expr =
      (support.evalFloe {
        name = "kapp";
        inputs.waitTimeout = "90s";
      }).provides.delivery.waitTimeout;
    expected = "90s";
  };

  # Nothing installs, so there is no component to emit and nothing in the
  # install graph waits on it.
  testItInstallsNothing = {
    expr = r.link.out ? "catallaxy.component";
    expected = false;
  };
}
