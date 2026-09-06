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

  # ---- externals: a hole answered from outside this link -------------------
  #
  # One floe requiring INGRESS and nothing in the link providing it, so the
  # only thing that can answer is the `external` argument. Everything the
  # tests below assert is about *that* seam.
  # It provides an echo of what it resolved, which is what makes these tests
  # bite: a floe that only *declares* a hole forces nothing when its provides
  # are read, so a link that silently failed to resolve would pass. Three of
  # these tests passed for exactly that reason before the echo existed.
  ECHO = floe.mkSig {
    name = "ECHO";
    fields.v = T.str;
  };

  # Two consumers of one signature: one reads a portable field, one reads a
  # local one. That pair is the point of typing locality per field rather than
  # per signature — the same external is correct for the first and an error
  # for the second.
  mkConsumer =
    { name, field }:
    floe.mkFloe {
      inherit name;
      requires.ingress = MIXED_INGRESS;
      provides.echo = ECHO;
      modules = [
        (
          { config, ... }:
          {
            config.floe.provides.echo.v = config.floe.requires.ingress.${field};
          }
        )
      ];
    };

  consumer = mkConsumer {
    name = "consumer";
    field = "baseDomain";
  };
  localConsumer = mkConsumer {
    name = "local-consumer";
    field = "className";
  };

  # `baseDomain` travels. `className` is an ingress class registered in the
  # cluster that provided it and means nothing anywhere else.
  MIXED_INGRESS = floe.mkSig {
    name = "INGRESS";
    fields = fixture.sigs.INGRESS.fields // {
      className = T.local T.str;
    };
  };

  # Every field local, so nothing in it would be readable here.
  ALL_LOCAL = floe.mkSig {
    name = "ALL_LOCAL";
    fields.crdKinds = T.local (T.listOf T.str);
  };

  externalIngress = {
    sig = MIXED_INGRESS;
    origin = "cluster 'mgmt'";
    value = {
      baseDomain = "elsewhere.example.com";
      className = "nginx";
      # The token shape `mkDeferred` produces, written out: the constructor
      # is bound to a unit of the link, and this value comes from outside one.
      address = {
        __deferred = true;
        source = "mgmt/ingress";
        path = [ "address" ];
        phase = "post-apply";
      };
    };
  };

  withExternal =
    ext:
    floe.link {
      units.consumer = consumer.instantiate { };
      scope = ext;
    };

  linkedExternally = withExternal { ingress = externalIngress; };

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

  # ---- externals ----------------------------------------------------------

  # The whole point: a hole nothing in this link provides, answered anyway.
  # Without `external` this link is a "no provider for signature" throw.
  # The whole point, read through the body: the value crossed the boundary,
  # was sealed, reached `config.floe.requires`, and came back out.
  testAScopeProvideAnswersAHole = {
    expr = linkedExternally.provides.consumer.echo.v;
    expected = "elsewhere.example.com";
  };

  # A link with the hole and no external is still the error it always was.
  # The paired negative, so the test above cannot pass for the wrong reason.
  testWithoutTheScopeTheHoleIsUnfilled = {
    expr = fails (withExternal { }).provides.consumer.echo.v;
    expected = true;
  };

  # Sealed like any other provide. A value assembled outside this link is the
  # least likely place for a wrong shape to be noticed, and a body reading a
  # field that is not there fails far from the cause.
  testAScopeProvideIsSealedAgainstItsSignature = {
    expr =
      fails
        (withExternal {
          ingress = externalIngress // {
            value = removeAttrs externalIngress.value [ "className" ];
          };
        }).provides.consumer.echo.v;
    expected = true;
  };

  # Exactly-one holds across the boundary too: a unit provider and an external
  # one are two providers, and picking either would be arbitrary.
  # Nearer wins: a unit of this link shadows a provider from the enclosing
  # scope rather than colliding with it. That is what makes a lab-wide offer
  # safe — a cluster with its own gateway keeps it, and one without picks up
  # the lab's.
  #
  # This is the behaviour change the scope was built for. It used to be a
  # refusal for "two providers", which meant offering anything lab-wide broke
  # every cluster that already had one.
  testALocalProviderShadowsTheScope = {
    expr =
      (floe.link {
        units = {
          consumer = consumer.instantiate { };
          ingress = fixture.floes.nginxIngress.instantiate { baseDomain = "lab.example.com"; };
        };
        scope.ingress = externalIngress;
      }).provides.consumer.echo.v;
    expected = "lab.example.com";
  };

  # An external is not a node, so it is not in the graph and orders nothing.
  # Whatever backs it is applied by a different pass entirely, and an edge
  # here would be an edge to a node that does not exist.
  testAScopeProvideAddsNoEdgeAndNoNode = {
    expr = {
      nodes = linkedExternally.graph.nodes;
      edges = linkedExternally.graph.edges;
    };
    expected = {
      nodes = [ "consumer" ];
      edges = [ ];
    };
  };

  # `wiring.one` is what every existing reader walks to derive order, so an
  # externally-resolved hole must not appear in it. It appears in `external`
  # instead, which is how a reader that *does* care can ask.
  testScopeHolesAreReportedApartFromLocalOnes = {
    expr = {
      one = linkedExternally.wiring.one.consumer;
      scope = linkedExternally.wiring.scope.consumer;
    };
    expected = {
      one = { };
      scope.ingress.scope = "ingress";
    };
  };

  # ---- locality ------------------------------------------------------------

  # A local field is ordinary inside the link that produced it. Locality is
  # about which link is *reading*, so it can never be a check on the value.
  testALocalFieldIsOrdinaryAtHome = {
    expr =
      (floe.link {
        units = {
          ingress = fixture.floes.nginxIngress.instantiate { baseDomain = "lab.example.com"; };
          local-consumer = localConsumer.instantiate { };
        };
      }).provides.local-consumer.echo.v;
    expected = "nginx";
  };

  # And an error the moment it is read through an external, because there is
  # no value that would be right — not because this one failed a check.
  testReadingALocalFieldAcrossALinkIsAnError = {
    expr =
      fails
        (floe.link {
          units.local-consumer = localConsumer.instantiate { };
          scope.ingress = externalIngress;
        }).provides.local-consumer.echo.v;
    expected = true;
  };

  # The paired positive, and the reason this is per field: the *same* external
  # read for something that does travel is correct. Without it the throw above
  # could be any failure at all.
  testAPortableFieldOnTheSameScopeProvideStillReads = {
    expr = linkedExternally.provides.consumer.echo.v;
    expected = "elsewhere.example.com";
  };

  # Nothing portable in it, so a hole resolved against it resolves to nothing
  # usable. Refused up front rather than at whichever field is touched first,
  # and derived from the fields — so a signature that gains a routed address
  # starts crossing without anyone remembering to say so.
  #
  # The consumer's own hole is filled here on purpose. Without that, this link
  # fails for "no provider for INGRESS" and the test passes whatever the
  # refusal does — which is how five refusals in `nix/checks/secret-sharing.nix`
  # once passed for the wrong reason.
  testAnAllLocalSignatureIsRefusedFromScope = {
    expr =
      fails
        (floe.link {
          units.consumer = consumer.instantiate { };
          scope = {
            ingress = externalIngress;
            other = {
              sig = ALL_LOCAL;
              origin = "cluster 'mgmt'";
              value.crdKinds = [ "kind:example.io/Widget" ];
            };
          };
        }).provides;
    expected = true;
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
