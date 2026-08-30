# Composing a cluster out of floes: the join, and what it derives.
#
# This is the cluster-component test — it stops at the cluster picture and
# never builds a lab, so the merge semantics can be iterated on without
# standing anything up. What it pins:
#
#   1. the join is a monoid: identity both sides, associative
#   2. two floes' contributions merge, and neither can reach the other's keys
#   3. install order is derived, including the edge between two floes that
#      neither of them wrote
#   4. the errors a wrong composition produces
{ lib }:

let
  floe = import ../floe-core { inherit lib; };
  kinds = import ../floe-catallaxy/component.nix { inherit lib floe; };
  sigs = import ../floe-catallaxy/sigs.nix { inherit floe; };
  policies = import ../floe-catallaxy/policies.nix { inherit lib; };
  elaborate = import ../floe-catallaxy/elaborate.nix { inherit lib; };

  inherit (kinds)
    mkBundle
    mkOpsCommand
    mkComponent
    mkHelmChart
    empty
    join
    qualify
    ;

  # The real table is generated per Kubernetes version and is large; the test
  # needs only the dividing line between "the API server ships this" and
  # "something has to install a CRD first".
  coreKinds = {
    Deployment = true;
    Service = true;
    ConfigMap = true;
    Namespace = true;
    Secret = true;
  };

  clusterKind = floe.mkOutputKind {
    name = "catallaxy.cluster";
    schema = floe.T.attrsOf floe.T.any;
  };

  # ---- fixtures ----------------------------------------------------------

  clusterFloe = floe.mkFloe {
    name = "k3d";
    provides.cluster = sigs.KUBERNETES_CLUSTER;
    out.cluster = clusterKind;
    modules = [
      {
        config.floe.provides.cluster = {
          name = "app";
          version = "1.31";
          context = "k3d-app";
          podSubnet = "10.244.0.0/16";
          serviceSubnet = "10.96.0.0/12";
        };
        config.floe.out.cluster.name = "app";
      }
    ];
  };

  crdsFloe = floe.mkFloe {
    name = "crds";
    requires.cluster = sigs.KUBERNETES_CLUSTER;
    provides.api = sigs.GATEWAY_API;
    out.component = kinds.component;
    modules = [
      {
        config.floe.provides.api = {
          version = "v1.2.1";
          crdKinds = [
            "kind:gw.example.com/Gateway"
            "kind:gw.example.com/HTTPRoute"
          ];
        };
        config.floe.out.component = mkComponent {
          backs.api = [ "crds" ];
          bundles.crds = mkBundle {
            yamls = [ "/dev/null" ];
            crds = [
              "gw.example.com/Gateway"
              "gw.example.com/HTTPRoute"
            ];
          };
        };
      }
    ];
  };

  gatewayFloe = floe.mkFloe {
    name = "gateway";
    requires.cluster = sigs.KUBERNETES_CLUSTER;
    requires.gatewayApi = sigs.GATEWAY_API;
    provides.gateway = sigs.API_GATEWAY;
    out.component = kinds.component;
    modules = [
      {
        config.floe.provides.gateway = {
          className = "traefik";
          baseDomain = "lab.test";
          parentRef = {
            name = "default-gateway";
            namespace = "kube-system";
            sectionName = "http";
          };
        };
        config.floe.out.component = mkComponent {
          backs.gateway = [
            "controller"
            "gateway"
          ];
          bundles = {
            controller = mkBundle {
              helmCharts.traefik = mkHelmChart {
                chart = "/dev/null";
                releaseName = "traefik";
                namespace = "kube-system";
              };
              ready = {
                kind = "condition";
                resource = "deployment/traefik";
                namespace = "kube-system";
                condition = "Available";
              };
              ops.gateway.listeners = mkOpsCommand {
                description = "Show the listeners";
                command = [ "kubectl" ];
              };
            };
            gateway = mkBundle {
              needs = [ "controller" ];
              resources.gw = {
                apiVersion = "gw.example.com/v1";
                kind = "Gateway";
                metadata = {
                  name = "default-gateway";
                  namespace = "kube-system";
                };
              };
              lint.route-listener-exists = {
                description = "Routes attach to a declared listener";
                severity = "error";
                scope = "per-cluster";
                format = "json";
                command = "true";
              };
            };
          };
        };
      }
    ];
  };

  # Declares no ordering of any kind: no `needs`, no token, nothing naming
  # the gateway. Every edge it ends up with is derived.
  serviceFloe = floe.mkFloe {
    name = "svc";
    requires.cluster = sigs.KUBERNETES_CLUSTER;
    requires.gateway = sigs.API_GATEWAY;
    out.component = kinds.component;
    modules = [
      (
        { config, ... }:
        {
          config.floe.out.component = mkComponent {
            bundles.app = mkBundle {
              createNamespaces = [ "svc" ];
              resources = {
                dep = {
                  apiVersion = "apps/v1";
                  kind = "Deployment";
                  metadata = {
                    name = "svc";
                    namespace = "svc";
                  };
                };
                route = {
                  apiVersion = "gw.example.com/v1";
                  kind = "HTTPRoute";
                  metadata = {
                    name = "svc";
                    namespace = "svc";
                  };
                  spec = {
                    hostnames = [ "svc.${config.floe.requires.gateway.baseDomain}" ];
                    parentRefs = [ config.floe.requires.gateway.parentRef ];
                  };
                };
              };
              verify.answers = {
                description = "The route answers";
                timeout = "2m";
                expect = null;
                reject = [ ];
              };
            };
          };
        }
      )
    ];
  };

  linkOf =
    units:
    floe.link {
      inherit units;
      policies = [
        policies.oneCluster
        policies.componentsTargetTheCluster
        policies.needsNameSiblings
        policies.backsNameOwnBundles
      ];
    };

  fullLink = linkOf {
    k3d = clusterFloe.instantiate { };
    crds = crdsFloe.instantiate { };
    gateway = gatewayFloe.instantiate { };
    svc = serviceFloe.instantiate { };
  };

  cluster = elaborate.elaborateCluster {
    linkResult = fullLink;
    inherit coreKinds;
  };

  waveNames = map (w: map (b: b.name) w) cluster.waves;

  # ---- monoid fixtures ---------------------------------------------------

  compA = qualify "a" (mkComponent {
    bundles.one = mkBundle { createNamespaces = [ "a" ]; };
    backs.p = [ "one" ];
  });
  compB = qualify "b" (mkComponent {
    bundles.two = mkBundle { };
  });
  compC = qualify "c" (mkComponent {
    bundles.three = mkBundle { };
  });

  # ---- failure fixtures --------------------------------------------------

  fails = expr: !(builtins.tryEval (builtins.deepSeq expr "evaluated")).success;

  noProvider =
    fails
      (linkOf {
        k3d = clusterFloe.instantiate { };
        svc = serviceFloe.instantiate { };
      }).graph;

  twoProviders =
    fails
      (linkOf {
        k3d = clusterFloe.instantiate { };
        crds = crdsFloe.instantiate { };
        gateway = gatewayFloe.instantiate { };
        gateway2 = gatewayFloe.instantiate { };
        svc = serviceFloe.instantiate { };
      }).graph;

  floeWith =
    component:
    floe.mkFloe {
      name = "broken";
      requires.cluster = sigs.KUBERNETES_CLUSTER;
      out.component = kinds.component;
      modules = [ { config.floe.out.component = component; } ];
    };

  elaborated =
    component:
    elaborate.elaborateCluster {
      linkResult = linkOf {
        k3d = clusterFloe.instantiate { };
        broken = (floeWith component).instantiate { };
      };
      inherit coreKinds;
    };

  probeMissingAField =
    fails
      (elaborated (mkComponent {
        bundles.b = mkBundle {
          resources.c = {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata.name = "c";
          };
          # A `condition` probe needs `resource`. Without it the wait renders
          # with an empty argument and times out instead of failing.
          ready = {
            kind = "condition";
            condition = "Available";
          };
        };
      })).waves;

  needsAStranger =
    fails
      (linkOf {
        k3d = clusterFloe.instantiate { };
        broken =
          (floeWith (mkComponent {
            bundles.b = mkBundle { needs = [ "not-mine" ]; };
          })).instantiate
            { };
      }).graph;

  namespaceWithNoCreator =
    fails
      (elaborated (mkComponent {
        bundles.b = mkBundle {
          resources.c = {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata = {
              name = "c";
              namespace = "nobody-makes-this";
            };
          };
        };
      })).waves;

  # ---- secret fixtures ---------------------------------------------------

  podReading = secret: {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "w";
      namespace = "app";
    };
    spec.template.spec.containers = [
      { env = [ { valueFrom.secretKeyRef.name = secret; } ]; }
    ];
  };

  secretResource = name: {
    apiVersion = "v1";
    kind = "Secret";
    metadata = {
      inherit name;
      namespace = "app";
    };
  };

  secretNobodyMakes =
    fails
      (elaborated (mkComponent {
        bundles.b = mkBundle {
          createNamespaces = [ "app" ];
          resources.w = podReading "absent";
        };
      })).waves;

  # The same reference, once something creates it.
  secretMadeBySibling = elaborated (mkComponent {
    bundles.maker = mkBundle {
      createNamespaces = [ "app" ];
      resources.s = secretResource "shared";
    };
    bundles.reader = mkBundle { resources.w = podReading "shared"; };
  });

  secretMadeAndReadTogether = elaborated (mkComponent {
    bundles.b = mkBundle {
      createNamespaces = [ "app" ];
      resources = {
        s = secretResource "own";
        w = podReading "own";
      };
    };
  });

  secretFromOutside = elaborated (mkComponent {
    bundles.b = mkBundle {
      createNamespaces = [ "app" ];
      externalSecrets = [ "app/seeded" ];
      resources.w = podReading "seeded";
    };
  });

  # A reference eval cannot see, because it reaches the chart as a value.
  invisibleReferenceUndeclared =
    fails
      (elaborated (mkComponent {
        bundles.b = mkBundle {
          createNamespaces = [ "app" ];
          needsSecrets = [ "app/by-helm-value" ];
        };
      })).waves;

  wildcardSatisfiesEveryNamespace = elaborated (mkComponent {
    bundles.maker = mkBundle {
      createNamespaces = [ "app" ];
      secrets = [ "*/everywhere" ];
    };
    bundles.reader = mkBundle { resources.w = podReading "everywhere"; };
  });

  waveOf =
    c: bundleName:
    let
      hits = lib.filter (e: lib.any (b: b.name == bundleName) e.wave) (
        lib.imap0 (i: wave: { inherit i wave; }) c.waves
      );
    in
    if hits == [ ] then null else (lib.head hits).i;

in
lib.runTests {

  # ---- 1. the join is a monoid -------------------------------------------
  #
  # Worth asserting rather than assuming. The design this replaced could state
  # none of these about itself: its collector returned an unrealised
  # `mkMerge`, so associativity was the module system's property and not the
  # function's, and there was nothing to write a test against.

  testLeftIdentity = {
    expr = join empty compA;
    expected = compA;
  };

  testRightIdentity = {
    expr = join compA empty;
    expected = compA;
  };

  testAssociative = {
    expr = join (join compA compB) compC;
    expected = join compA (join compB compC);
  };

  # Keys are unit-qualified, so no two floes can produce the same one and the
  # join is total. That is what makes it a monoid rather than a partial
  # operation that throws on collision.
  testJoinIsCommutativeOnDisjointDomains = {
    expr = join compA compB == join compB compA;
    expected = true;
  };

  # ---- 2. merge semantics ------------------------------------------------

  testEveryFloesBundlesArePresentAndQualified = {
    expr = lib.attrNames cluster.bundles;
    expected = [
      "crds/crds"
      "gateway/controller"
      "gateway/gateway"
      "svc/app"
    ];
  };

  # `needs` names a sibling in the floe's own namespace and is resolved into
  # the joined one, so a floe cannot reach another's bundle by naming it.
  testNeedsIsResolvedIntoTheJoinedNamespace = {
    expr = cluster.bundles."gateway/gateway".needs;
    expected = [ "gateway/controller" ];
  };

  testDeclaredByIsStampedByTheJoin = {
    expr = lib.mapAttrs (_: b: b.declaredBy) cluster.bundles;
    expected = {
      "crds/crds" = "crds";
      "gateway/controller" = "gateway";
      "gateway/gateway" = "gateway";
      "svc/app" = "svc";
    };
  };

  # The operator surface is written on the bundle, for locality, and read at
  # the cluster. Ops keep their category so `<lab>-ops <category> <name>`
  # still addresses them.
  testOpsAreLiftedKeepingTheirCategory = {
    expr = lib.mapAttrs (_: lib.attrNames) cluster.ops;
    expected.gateway = [ "gateway-controller-listeners" ];
  };

  # `<unit>-<bundle>` collapses to one when they are the same word, which is
  # the shape of every single-bundle floe. Without it velero's commands reach
  # the operator as `velero-velero-create`, and this is the one surface where
  # the name is something a person types rather than something a tool reads.
  testOpsDoNotRepeatAUnitNamedAfterItsOnlyBundle =
    let
      solo = floe.mkFloe {
        name = "velero";
        out.component = kinds.component;
        modules = [
          {
            config.floe.out.component = mkComponent {
              bundles.velero = mkBundle {
                resources = { };
                ops.backup.create = mkOpsCommand {
                  description = "Create a backup";
                  command = [ "velero" ];
                };
              };
            };
          }
        ];
      };
      # No policies: `oneCluster` would want a cluster floe, and this is
      # about the name the join produces, not about a well-formed cluster.
      linked = floe.link {
        units.velero = solo.instantiate { };
        policies = [ ];
      };
    in
    {
      expr = lib.attrNames (elaborate.elaborateCluster { linkResult = linked; }).ops.backup;
      expected = [ "velero-create" ];
    };

  testLintAndVerifyAreLiftedAndQualified = {
    expr = {
      lint = lib.attrNames cluster.lint;
      verify = lib.attrNames cluster.verify;
    };
    expected = {
      lint = [ "gateway/gateway/route-listener-exists" ];
      verify = [ "svc/app/answers" ];
    };
  };

  testNamespacesAreTheUnionOfWhatBundlesCreate = {
    expr = cluster.namespaces;
    expected = [ "svc" ];
  };

  # A record rather than a bare hostname: `cata lab verify` probes these, and
  # a failing probe has to name the bundle that declared the route.
  testExposedHostsAreReadOffTheRoutes = {
    expr = cluster.exposedHosts;
    expected = [
      {
        host = "svc.lab.test";
        namespace = "svc";
        bundle = "svc/app";
        tier = "public";
        paths = [ ];
      }
    ];
  };

  # ---- 3. derived install order ------------------------------------------

  # CRDs, then the controller, then the Gateway, then the service. Only one
  # of those three edges was written by anyone: `gateway.needs`.
  testWavesAreDerived = {
    expr = waveNames;
    expected = [
      [
        "crds/crds"
        "namespaces"
      ]
      [ "gateway/controller" ]
      [ "gateway/gateway" ]
      [ "svc/app" ]
    ];
  };

  # The service names nothing of the gateway's. The edge comes from the link
  # graph — svc resolved API_GATEWAY to gateway — crossed with the gateway's
  # own `backs`, which says which of its bundles stand behind that promise.
  testTheCrossFloeEdgeIsDerivedNotDeclared = {
    expr = {
      declared = cluster.bundles."svc/app".needs;
      derived = cluster.graphBundles."svc/app".requires;
    };
    expected = {
      declared = [ ];
      derived = [
        "bundle:gateway/controller"
        "bundle:gateway/gateway"
        "kind:gw.example.com/HTTPRoute"
      ];
    };
  };

  # A bundle whose CRDs arrive as an upstream YAML file has none in
  # `resources` for the graph to read, so it declares them — and that is what
  # the consumer's derived `kind:` requirement resolves against.
  testYamlSourcedCrdsSatisfyDerivedKindRequirements = {
    expr = lib.elem "kind:gw.example.com/HTTPRoute" cluster.graphBundles."crds/crds".provides;
    expected = true;
  };

  # ---- 4. failures -------------------------------------------------------

  testNoProviderFails = {
    expr = noProvider;
    expected = true;
  };

  testTwoProvidersFail = {
    expr = twoProviders;
    expected = true;
  };

  testAProbeMissingARequiredFieldFails = {
    expr = probeMissingAField;
    expected = true;
  };

  testNeedsNamingAStrangerFails = {
    expr = needsAStranger;
    expected = true;
  };

  # Neither floe can answer this alone: the one that creates a namespace and
  # the one that installs into it are usually different. It is a check that
  # exists only once the components are joined.
  testANamespaceWithNoCreatorFails = {
    expr = namespaceWithNoCreator;
    expected = true;
  };

  # ---- secrets -----------------------------------------------------------
  #
  # The same shape of check as the namespace one above, for the same reason: a
  # floe reading a Secret is rarely the floe that makes it.

  testASecretWithNoCreatorFails = {
    expr = secretNobodyMakes;
    expected = true;
  };

  # The reference the walk cannot see is the common case — a credential that
  # reaches a chart as a value — and it has to be refused too, or declaring it
  # would be optional and nobody would.
  testAnInvisibleReferenceMustStillBeDeclared = {
    expr = invisibleReferenceUndeclared;
    expected = true;
  };

  # Ordering nobody wrote: the reader names no bundle and the maker names no
  # reader, and the graph still puts them in that order.
  testAReaderLandsAfterTheBundleThatMakesItsSecret = {
    expr = waveOf secretMadeBySibling "broken/maker" < waveOf secretMadeBySibling "broken/reader";
    expected = true;
  };

  # One bundle doing both is self-satisfied. An edge here would be a bundle
  # waiting on itself, which is a cycle rather than an ordering.
  testMakingAndReadingInOneBundleIsNotACycle = {
    expr = builtins.length secretMadeAndReadTogether.waves > 0;
    expected = true;
  };

  # `cert-generate` and an operator both land Secrets no manifest contains.
  testAnExternallySuppliedSecretSatisfiesTheCheck = {
    expr = secretFromOutside.runtimeMaterialised;
    expected = [ "app/seeded" ];
  };

  # A trust-manager Bundle with an empty `namespaceSelector` writes into every
  # namespace, which the floe cannot enumerate and the cluster can.
  testAWildcardCoversEveryNamespace = {
    expr = waveOf wildcardSatisfiesEveryNamespace "broken/reader" != null;
    expected = true;
  };
}
