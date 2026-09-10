# external-secrets, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "external-secrets";
    inputs = {
      chart = "/dev/null";
      crds = "/dev/null";
    };
  };
in
lib.runTests {

  # A `sourceRef.generatorRef` naming the wrong API version is admitted and
  # then never reconciles, so the version is part of the capability rather
  # than something a consumer guesses.
  testNamesTheGeneratorApiVersion = {
    expr = r.provides.generation.generatorApiVersion;
    expected = "generators.external-secrets.io/v1alpha1";
  };

  # It installs a controller and creates no store, so it cannot answer
  # SECRET_STORE — which is why that signature was split in two.
  testDoesNotClaimToBeAStore = {
    expr = r.provides ? store;
    expected = false;
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

}
