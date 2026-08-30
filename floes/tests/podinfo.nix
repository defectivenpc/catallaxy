# podinfo, alone.
#
# The test service, and the one that pins the point of the whole exercise:
# it names nothing of the gateway's, and it declares no ordering.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe { name = "podinfo"; };

  route = r.bundles.podinfo.resources.podinfo-route;
in
lib.runTests {

  # Straight off the sealed API_GATEWAY value. podinfo spells neither the
  # gateway's name, nor its namespace, nor its listener.
  testTheRouteAttachesToWhateverProvidedTheGateway = {
    expr = lib.head route.spec.parentRefs;
    expected = {
      name = "stub-gateway";
      namespace = "kube-system";
      sectionName = "https";
    };
  };

  # And its hostname hangs off the gateway's zone rather than a lab option
  # it read for itself.
  testTheHostnameComesFromTheGatewaysZone = {
    expr = route.spec.hostnames;
    expected = [ "podinfo.stub.test" ];
  };

  # What the gateway collects. This replaced eight consumers writing into
  # `floes.gateway.internalHostnames`.
  testItAsksToBeRouted = {
    expr = r.provides.route;
    expected = {
      hostname = "podinfo.stub.test";
      tier = "public";
    };
  };

  # No `needs`, no token, nothing naming the gateway. Every edge it ends up
  # with is derived.
  testItDeclaresNoOrdering = {
    expr = r.bundles.podinfo.needs;
    expected = [ ];
  };

  testItCreatesItsOwnNamespace = {
    expr = r.bundles.podinfo.createNamespaces;
    expected = [ "podinfo" ];
  };
}
