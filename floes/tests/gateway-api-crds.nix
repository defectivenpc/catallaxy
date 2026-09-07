# gateway-api-crds, alone.
#
# The shipped tree installed these through `cluster.prerequisites`, a
# mechanism that exists because gateway and cilium both need them and a
# bundle declared by two floes is a conflicting definition. Exactly-one
# provider is that rule already.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "gateway-api-crds";
    inputs = {
      manifest = "/dev/null";
      version = "v1.2.1";
    };
  };
in
lib.runTests {

  # They arrive as an upstream YAML file, which eval cannot see inside, so
  # the bundle declares what it installs. Every consumer's derived `kind:`
  # requirement resolves against this.
  testDeclaresTheKindsItInstalls = {
    expr = lib.elem "gateway.networking.k8s.io/HTTPRoute" r.bundles.crds.crds;
    expected = true;
  };

  testInstallsInfraAndRouteKinds = {
    expr = builtins.length r.bundles.crds.crds;
    expected = 10;
  };

  testProvidesTheVersionItInstalled = {
    expr = r.provides.gatewayApi.version;
    expected = "v1.2.1";
  };
}
