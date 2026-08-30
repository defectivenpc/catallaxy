# delivery, alone.
#
# The one floe that installs nothing: it carries a policy value so a floe
# rendering differently under GitOps can ask, rather than reading a lab
# option and coupling itself to the lab's shape.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe { name = "delivery"; };
in
lib.runTests {

  testInstallsNothing = {
    expr = r.bundles;
    expected = { };
  };

  # And therefore requires no cluster. `componentsTargetTheCluster` checks
  # units that render bundles, not units that emit a component, which is why
  # this floe does not have to name a cluster it never touches.
  testNeedsNoCluster = {
    expr =
      lib.attrNames
        (import ../cluster/delivery {
          inherit lib pkgs;
          inherit (support.catallaxy) floe sigs kinds;
        }).requires;
    expected = [ ];
  };

  testDefaultsToDirectApply = {
    expr = r.provides.policy;
    expected = {
      strategy = "kapp";
      bootstrapTool = "kubectl-ssa";
      appliedByKapp = true;
    };
  };
}
