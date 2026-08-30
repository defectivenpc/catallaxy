# Pins floe-core's linking behaviour against the worked example in
# `support/floe-core`: hole resolution, sealing, and the two edge kinds.
{ lib }:

let
  floe = import ../floe-core { inherit lib; };
  fixture = import ./support/floe-core { inherit lib floe; };

  T = floe.T;
  SELF = floe.mkSig {
    name = "SELF";
    fields.v = T.str;
  };

  # One floe, one signature, and a switch for whether it also asks for it.
  selfLink =
    { asksForIt }:
    let
      u = floe.mkFloe (
        {
          name = "narcissus";
          provides.it = SELF;
          modules = [
            {
              config.floe.provides.it = {
                v = "mine";
              };
            }
          ];
        }
        // lib.optionalAttrs asksForIt { requires.it2 = SELF; }
      );
    in
    floe.link { units.narcissus = u.instantiate { }; };

  fails = expr: !(builtins.tryEval (builtins.deepSeq expr "evaluated")).success;

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

  # An optional hole that resolved arrives as the sealed value itself, the
  # same as an exactly-one hole — the only difference between the two is that
  # this one may be `null`. It used to be `requiresMany` and arrive keyed by
  # providing unit; the fan-in went because it collected in the one direction
  # that made ordering run backwards.
  testAResolvedOptionalHoleIsTheSealedValue = {
    expr = deployment.provides.grafana.observer.dashboards;
    expected = {
      myapp.url = "https://grafana.lab.example.com/d/app-myapp";
    };
  };

  # `providersOf` scans every unit including the requester, so this used to
  # resolve to itself: no error, and no second provider to disambiguate
  # against. The failures are quiet — an otel-collector providing TRACE_INGEST
  # would have exported into its own receiver.
  testAFloeDoesNotSatisfyItsOwnHole = {
    expr = fails (selfLink { asksForIt = true; }).provides;
    expected = true;
  };

  # The paired positive. Without it the refusal above could pass because the
  # fixture fails to link for some unrelated reason, which is how five
  # refusals in nix/checks/secret-sharing.nix once passed for the wrong one.
  testTheSameFloeLinksFineWhenItOnlyProvides = {
    expr = (selfLink { asksForIt = false; }).provides.narcissus.it;
    expected = {
      v = "mine";
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
