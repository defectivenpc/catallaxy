# kaniop, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "kaniop";
    inputs.chart = "/dev/null";
  };
in
lib.runTests {

  testProvidesItsSignature = {
    expr = r.provides.operator.readyToken;
    expected = "kaniop/operator/ready";
  };

  # A floe that renders nothing has nothing to install, and every consumer's
  # ordering edge into it would resolve to an empty set.
  testRendersSomething = {
    expr = r.bundles != { };
    expected = true;
  };

  # Its image set is exhaustive, so the cluster may check that claim against
  # what it actually rendered.
  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  # A floe that says nothing about its network is indistinguishable from one
  # nobody has looked at.
  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
