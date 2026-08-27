# Pins floe-core's linking behaviour against the worked example in
# `support/floe-core`: hole resolution, sealing, and the two edge kinds.
{ lib }:

let
  floe = import ../floe-core { inherit lib; };
  fixture = import ./support/floe-core { inherit lib floe; };

  deployment = fixture.deployment;

  # Edges are compared as sorted strings: the linker's list order follows
  # attribute order, which is an implementation detail the test should not pin.
  edge = e: "${e.kind}:${e.from}->${e.to} via ${e.via}";
  edges = lib.sort (a: b: a < b) (map edge deployment.graph.edges);
in
lib.runTests {

  testNodesAreTheUnitNames = {
    expr = deployment.graph.nodes;
    expected = [
      "grafana"
      "ingress"
      "myapp"
    ];
  };

  # An eval edge says A needed B's config to render. Three of them: grafana
  # resolved its INGRESS hole, grafana's fan-in collected myapp's
  # DASHBOARD_REQ, and myapp resolved OBSERVER back to grafana. That last
  # pair is a cycle, and laziness carries it.
  #
  # The deploy edge is derived, not declared: grafana interpolated
  # nginx-ingress's deferred LoadBalancer address into out.k8s, and the
  # link-time scan found the token.
  testEdges = {
    expr = edges;
    expected = [
      "deploy:grafana->ingress via status.loadBalancer.ip"
      "eval:grafana->ingress via ingress"
      "eval:grafana->myapp via dashboards"
      "eval:myapp->grafana via observer"
    ];
  };

  # Phases fall out of the deploy subgraph alone. myapp is phase 0 despite
  # depending on grafana at eval time, because nothing it emits waits on
  # anything grafana applies.
  testPhases = {
    expr = deployment.phases;
    expected = {
      grafana = 1;
      ingress = 0;
      myapp = 0;
    };
  };

  # Sealing restricts to the signature. grafana's body defines exactly these
  # two, but a body defining more would still surface only these.
  testProvidesAreSealedToTheSignature = {
    expr = lib.attrNames deployment.provides.grafana.observer;
    expected = [
      "dashboards"
      "ingressUrl"
    ];
  };

  testProvidedValuesSurvive = {
    expr = deployment.provides.grafana.observer.ingressUrl;
    expected = "https://grafana.lab.example.com";
  };

  # The fan-in hole arrives keyed by providing unit name, so grafana can
  # name the requester without any unit having spelled the other's name.
  testFanInIsKeyedByUnit = {
    expr = deployment.provides.grafana.observer.dashboards;
    expected = {
      myapp.url = "https://grafana.lab.example.com/d/app-myapp";
    };
  };

  testOutputsAreCollectedByKind = {
    expr = lib.attrNames deployment.out;
    expected = [
      "catallaxy.meta"
      "k8s.manifests"
    ];
  };

  # Collection is keyed by unit and disjoint by construction: no merge.
  testOutputsAreKeyedByUnit = {
    expr = lib.attrNames deployment.out."k8s.manifests";
    expected = [
      "grafana"
      "ingress"
      "myapp"
    ];
  };
}
