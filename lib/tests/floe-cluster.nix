{
  lib,
  floeCore,
  specFile,
}:

let
  floe = import ../floe-catallaxy/authoring/prelude.nix { inherit lib floeCore; };

  k8sApi = import ../kubernetes/api.nix {
    inherit lib floeCore specFile;
    crdGroups = { };
  };

  kinds = import ../floe-catallaxy/domain/component.nix { inherit lib floe k8sApi; };
  sigs = import ../floe-catallaxy/domain/sigs.nix { inherit lib floe; };
  policies = import ../floe-catallaxy/domain/policies.nix { inherit lib sigs k8sApi; };
  elaborate = import ../lower/elaborate.nix { inherit lib floe k8sApi; };

  inherit (kinds)
    mkBundle
    mkOpsCommand
    mkComponent
    mkHelmChart
    empty
    join
    qualify
    ;

  coreKinds = {
    Deployment = true;
    Service = true;
    ConfigMap = true;
    Namespace = true;
    Secret = true;
  };

  clusterKind = floe.mkSig {
    name = "catallaxy.cluster";
    canonicalName = "clusterDescriptor";
    description = "Fixture kind: a permissive stand-in for the real cluster descriptor.";
    fields = floe.T.attrsOf floe.T.any;
  };

  clusterFloe = floe.mkFloe {
    name = "k3d";
    summary = "Fixture floe for a test suite.";
    provides.cluster = sigs.KUBERNETES_CLUSTER;
    out.clusterDescriptor = clusterKind;
    modules = [
      {
        config.floe.provides.cluster = {
          name = "app";
          version = "1.31";
          context = "k3d-app";
          podSubnet = "10.244.0.0/16";
          serviceSubnet = "10.96.0.0/12";
          assignsLoadBalancers = true;
        };
        config.floe.out.clusterDescriptor.name = "app";
      }
    ];
  };

  crdsFloe = floe.mkFloe {
    name = "crds";
    summary = "Fixture floe for a test suite.";
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
    summary = "Fixture floe for a test suite.";
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

  serviceFloe = floe.mkFloe {
    name = "svc";
    summary = "Fixture floe for a test suite.";
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
        policies.componentsTargetTheCluster
        policies.needsNameSiblings
        policies.backsNameOwnBundles
        policies.promisedHostsAreRouted
      ];
    };

  PROMISE = floe.mkSig {
    name = "fixture.promise";
    canonicalName = "promise";
    description = "Fixture: a provide carrying a URL.";
    fields = {
      url = floe.T.str;
    };
  };

  promiserFloe = floe.mkFloe {
    name = "promiser";
    summary = "Fixture floe for a test suite.";
    requires.cluster = sigs.KUBERNETES_CLUSTER;
    requires.gateway = sigs.API_GATEWAY;
    provides.promise = PROMISE;
    out.component = kinds.component;
    modules = [
      (
        { config, ... }:
        {
          config.floe.provides.promise.url = "https://orphan.${config.floe.requires.gateway.baseDomain}";
          config.floe.out.component = mkComponent {
            bundles.app = mkBundle { createNamespaces = [ "promiser" ]; };
          };
        }
      )
    ];
  };

  carrierFloe = floe.mkFloe {
    name = "carrier";
    summary = "Fixture floe for a test suite.";
    provides.promise = PROMISE;
    body = _: {
      provides.promise.url = "https://elsewhere.lab.test";
    };
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

  withPromiser = linkOf {
    k3d = clusterFloe.instantiate { };
    crds = crdsFloe.instantiate { };
    gateway = gatewayFloe.instantiate { };
    svc = serviceFloe.instantiate { };
    promiser = promiserFloe.instantiate { };
  };

  withCarrier = linkOf {
    k3d = clusterFloe.instantiate { };
    crds = crdsFloe.instantiate { };
    gateway = gatewayFloe.instantiate { };
    svc = serviceFloe.instantiate { };
    carrier = carrierFloe.instantiate { };
  };

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
      summary = "Fixture floe for a test suite.";
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

  podReading = secret: {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      name = "w";
      namespace = "app";
    };
    spec.selector.matchLabels.app = "w";
    spec.template.metadata.labels.app = "w";
    spec.template.spec.containers = [
      {
        name = "w";
        env = [
          {
            name = "FROM_SECRET";
            valueFrom.secretKeyRef = {
              name = secret;
              key = "value";
            };
          }
        ];
      }
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

  testAPromisedHostWithNoRouteIsRefused = {
    expr = fails withPromiser.graph;
    expected = true;
  };

  testACarriedPromiseIsNotThisClustersToRoute = {
    expr = fails withCarrier.graph;
    expected = false;
  };

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

  testJoinIsCommutativeOnDisjointDomains = {
    expr = join compA compB == join compB compA;
    expected = true;
  };

  testEveryFloesBundlesArePresentAndQualified = {
    expr = lib.attrNames cluster.bundles;
    expected = [
      "crds/crds"
      "gateway/controller"
      "gateway/gateway"
      "svc/app"
    ];
  };

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

  testOpsAreLiftedKeepingTheirCategory = {
    expr = lib.mapAttrs (_: lib.attrNames) cluster.ops;
    expected.gateway = [ "gateway-controller-listeners" ];
  };

  testOpsDoNotRepeatAUnitNamedAfterItsOnlyBundle =
    let
      solo = floe.mkFloe {
        name = "velero";
        summary = "Fixture floe for a test suite.";
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

  testYamlSourcedCrdsSatisfyDerivedKindRequirements = {
    expr = lib.elem "kind:gw.example.com/HTTPRoute" cluster.graphBundles."crds/crds".provides;
    expected = true;
  };

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

  testANamespaceWithNoCreatorFails = {
    expr = namespaceWithNoCreator;
    expected = true;
  };

  testASecretWithNoCreatorFails = {
    expr = secretNobodyMakes;
    expected = true;
  };

  testAnInvisibleReferenceMustStillBeDeclared = {
    expr = invisibleReferenceUndeclared;
    expected = true;
  };

  testAReaderLandsAfterTheBundleThatMakesItsSecret = {
    expr = waveOf secretMadeBySibling "broken/maker" < waveOf secretMadeBySibling "broken/reader";
    expected = true;
  };

  testMakingAndReadingInOneBundleIsNotACycle = {
    expr = builtins.length secretMadeAndReadTogether.waves > 0;
    expected = true;
  };

  testAnExternallySuppliedSecretSatisfiesTheCheck = {
    expr = secretFromOutside.runtimeMaterialised;
    expected = [ "app/seeded" ];
  };

  testAWildcardCoversEveryNamespace = {
    expr = waveOf wildcardSatisfiesEveryNamespace "broken/reader" != null;
    expected = true;
  };

  testAnImageIsReadOffTheRefAnOperatorWouldType = {
    expr = kinds.mkImage "quay.io/jetstack/trust-manager:v0.22.1";
    expected = {
      registry = "quay.io";
      repository = "jetstack/trust-manager";
      tag = "v0.22.1";
      digest = null;
    };
  };

  testADigestPinnedRefKeepsBothHalves = {
    expr = kinds.mkImage "quay.io/cilium/cilium:v1.17.2@sha256:deadbeef";
    expected = {
      registry = "quay.io";
      repository = "cilium/cilium";
      tag = "v1.17.2";
      digest = "sha256:deadbeef";
    };
  };

  testAProviderMissingItsObligationIsRefused = {
    expr =
      let
        result = {
          providersOf =
            sigName:
            lib.optional (sigName == "X509_ISSUANCE") {
              instName = "pretender";
              provideName = "issuance";
            };
          out."catallaxy.component".pretender = {
            bundles.only = {
              verify = { };
            };
          };
        };
      in
      lib.length (policies.providersVerifyWhatTheyPromise result);
    expected = 1;
  };

  testAProviderDeclaringItPasses = {
    expr =
      let
        result = {
          providersOf =
            sigName:
            lib.optional (sigName == "X509_ISSUANCE") {
              instName = "honest";
              provideName = "issuance";
            };
          out."catallaxy.component".honest = {
            bundles.only = {
              verify.issuers-ready = { };
            };
          };
        };
      in
      policies.providersVerifyWhatTheyPromise result;
    expected = [ ];
  };

  testAUnitWithNoComponentOwesNothing = {
    expr =
      let
        result = {
          providersOf =
            sigName:
            lib.optional (sigName == "X509_ISSUANCE") {
              instName = "from-outside/core/issuance";
              provideName = "issuance";
            };
          out."catallaxy.component" = { };
        };
      in
      policies.providersVerifyWhatTheyPromise result;
    expected = [ ];
  };

  testARegistryPortIsNotMistakenForATag = {
    expr = (kinds.mkImage "localhost:5000/app:v1").registry;
    expected = "localhost:5000";
  };

  testARefWithNoRegistryIsRefused = {
    expr = fails (kinds.mkImage "traefik:v3.3.6");
    expected = true;
  };

  testADockerHubNamespaceIsNotARegistry = {
    expr = fails (kinds.mkImage "chrislusf/seaweedfs:4.0.0");
    expected = true;
  };
}
