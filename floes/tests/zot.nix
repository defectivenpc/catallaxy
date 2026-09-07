# zot, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "zot";
    inputs.chart = "/dev/null";
  };

  values = r.bundles.zot.helmCharts.zot.values;
in
lib.runTests {

  # An image reference is not a URL. A consumer handed only one of these would
  # have to build the other by stripping a scheme, and would eventually get it
  # wrong somewhere nothing checks.
  testTheePullRefCarriesNoScheme = {
    expr = r.provides.registry.pullRef;
    expected = "zot.zot.svc.cluster.local:5000";
  };

  testTheUrlDoes = {
    expr = r.provides.registry.url;
    expected = "http://zot.zot.svc.cluster.local:5000";
  };

  # A boolean in this chart version, not an object. `{ enabled = true; }` is
  # also truthy and would pick the same workload while silently discarding the
  # size beside it — which is what the parked floe did.
  testPersistenceIsTheBooleanThisChartTakes = {
    expr = values.persistence;
    expected = true;
  };

  testTheClaimIsConfiguredWhereThisChartReadsIt = {
    expr = values.pvc.storage;
    expected = "8Gi";
  };

  # The chart defaults to NodePort, which publishes the registry on every node
  # of the cluster.
  testTheServiceIsNotPublishedOnEveryNode = {
    expr = values.service.type;
    expected = "ClusterIP";
  };

  # Open, and it says so rather than leaving a consumer to find out from a 401
  # in a Job's logs.
  testItAdmitsItTakesAnything = {
    expr = r.provides.registry.credentials;
    expected = null;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

}
