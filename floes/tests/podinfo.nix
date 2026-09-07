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

  # The route is the gateway's own constructor's output, not a hand-rolled
  # HTTPRoute. That is the whole of the routing inversion now: a consumer
  # requires API_GATEWAY and renders its own resource, and there is no
  # a route request for the gateway to collect.
  testTheRouteIsBuiltByTheGatewaysConstructor = {
    expr =
      route == support.catallaxy.kinds.mkRoute {
        gateway = support.stubs.apiGateway.value;
        name = "podinfo";
        namespace = "podinfo";
        service = "podinfo";
        port = 80;
      };
    expected = true;
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
