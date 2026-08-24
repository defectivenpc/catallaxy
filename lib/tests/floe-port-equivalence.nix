# Does porting a floe to the interface change what it produces?
#
# Each ported floe exists twice — `default.nix` in the shape as shipped, and
# `modular.nix` as an instance of `lib/floe/interface.nix`. Rendering is a pure
# function of the bundle data, so if the two produce equal `bundles`, `images`,
# `network` and `exports`, they render identical manifests, which is what the
# digest fixtures would otherwise have to prove through the whole pipeline.
#
# Asserted field by field rather than as one big equality, because a single
# `expected = { ... }` that fails tells you only that something moved.
#
#   - reloader is the small case: reads nothing, writes only its own bundles.
#   - gateway is the one that finds what is missing. It reads the cluster, reads
#     a peer at option-*default* time, and writes two cluster-scope channels, so
#     it exercises every mechanism the spike added.
{ lib, pkgs }:

let
  inherit (import ../floe { inherit lib; }) evalFloe;

  registry = import ../floe/registry.nix {
    inherit lib;
    modulesPath = ../../modules;
  };

  # ==========================================================================
  # reloader — the small case
  # ==========================================================================

  charts.reloader.chart = pkgs.emptyDirectory;

  # --- the shape as shipped -------------------------------------------------
  old =
    (evalFloe {
      floe = import ../../floes/cluster/reloader;
      cluster.floes.reloader.enable = true;
      args = {
        inherit pkgs;
        cataCharts = charts;
      };
    }).config.floes.reloader;

  # --- the same floe as an instance of the interface ------------------------
  new =
    (lib.evalModules {
      modules = [
        (registry.mkRegistryModule {
          lab = {
            name = "t";
            images = { };
          };
          args = {
            inherit pkgs;
            cataCharts = charts;
          };
        })
        {
          floeModules.reloader = import ../../floes/cluster/reloader/modular.nix;
          floes.reloader.enable = true;
        }
      ];
    }).config.floes.reloader;

  # `mkPatches` is a function, so it cannot be compared by value. Compare what
  # it *does* instead — a function that no longer produces the same patch is
  # the failure this is for, and equality of two closures would never catch it.
  sampleWorkload = [
    {
      kind = "Deployment";
      name = "app";
      secrets = [ "app-secret" ];
      configMaps = [ "app-config" ];
    }
  ];

  # ==========================================================================
  # gateway — the case that exercises reads, peers and cluster writes
  # ==========================================================================

  gatewayArgs = {
    inherit pkgs;
    cataCharts.traefik.chart = pkgs.emptyDirectory;
    k8sSpecs.standaloneCrds.gateway-api = "gateway-api-crds-stub";

    # `evalFloe` supplies this to the old shape from its own defaults; the
    # registry takes no defaults, so the harness names it. Same value.
    contracts = import ../contracts { inherit lib; };
  };

  # The lab facts gateway reads: `lab.dns.zone` for the certificate's name and
  # `lab.policy.exposure.defaultTier` for the tier it exports. `evalFloe`
  # supplies its own, so this only has to match it where gateway looks.
  gatewayLab = {
    name = "test-lab";
    images = { };
    dns.zone = "test.local";
    policy.exposure.defaultTier = "public";
  };

  # What cert-manager publishes. Gateway reads it in two places, and one of
  # them is the *default* of `tls.enable` — so if `peers` did not work before
  # the fixpoint settled, this is where it would show.
  certManagerIssuance = {
    clusterIssuer = "lab-ca";
  };

  # --- the shape as shipped -------------------------------------------------
  #
  # `cluster.*` is declared by the harness because gateway reads three of them
  # and writes two, and `evalFloe` brings in only `prerequisites.nix`. Same stub
  # as `floes/tests/gateway.nix` uses, for the same reason.
  stubCluster =
    publishesGatewayPorts:
    { lib, ... }:
    {
      options.cluster.network.serviceSubnet = lib.mkOption {
        type = lib.types.str;
        default = "10.96.0.0/12";
      };
      options.cluster.provisionerOut.publishesGatewayPorts = lib.mkOption {
        type = lib.types.bool;
        default = publishesGatewayPorts;
      };
      options.cluster.ingress.httpPort = lib.mkOption {
        type = lib.types.port;
        default = 80;
      };
      options.cluster.ingress.httpsPort = lib.mkOption {
        type = lib.types.port;
        default = 443;
      };
      options.cluster.ingress.passthroughPort = lib.mkOption {
        type = lib.types.port;
        default = 8444;
      };
    };

  oldGateway =
    {
      settings,
      publishesGatewayPorts ? true,
    }:
    (evalFloe {
      floe = import ../../floes/cluster/gateway;
      args = gatewayArgs // {
        lab = gatewayLab;
      };
      providers.cert-manager.issuance = certManagerIssuance;
      cluster = {
        imports = [ (stubCluster publishesGatewayPorts) ];
        floes.gateway = settings // {
          enable = true;
        };
      };
    }).config;

  # --- the same floe as an instance of the interface ------------------------
  #
  # cert-manager is a synthetic floe rather than the real one, because what is
  # under test is gateway's port, not cert-manager's. It declares exactly the
  # one export gateway reads.
  stubCertManager =
    { lib, ... }:
    {
      options.exports = lib.mkOption {
        type = lib.types.submodule {
          options.issuance = lib.mkOption {
            type = lib.types.nullOr lib.types.attrs;
            default = null;
          };
        };
      };
      config = {
        enable = true;
        exports.issuance = certManagerIssuance;
      };
    };

  # The fold. This is the half of the mechanism that is new, so it is evaluated
  # rather than simulated with `//`: the cluster declares its own `ingress` and
  # `prerequisites` and merges every floe's contribution into them, exactly as
  # `modules/lab/cluster/bundles.nix:44` already does for `bundles`.
  stubClusterFold =
    publishesGatewayPorts:
    { config, lib, ... }:
    {
      imports = [ (stubCluster publishesGatewayPorts) ];

      options.cluster.prerequisites = lib.mkOption {
        type =
          lib.types.attrsOf
            (import ../../modules/lab/cluster/prerequisite-types.nix { inherit lib; }).prerequisiteType;
        default = { };
      };

      config.cluster.ingress = lib.mkMerge (lib.mapAttrsToList (_: floe: floe.ingress) config.floes);
      config.cluster.prerequisites = lib.mkMerge (
        lib.mapAttrsToList (_: floe: floe.prerequisites) config.floes
      );
    };

  newGateway =
    {
      settings,
      publishesGatewayPorts ? true,
    }:
    (lib.evalModules {
      modules = [
        (registry.mkRegistryModule {
          lab = gatewayLab;
          args = gatewayArgs;

          # The read channel. Threaded from the enclosing config, which is what
          # a real cluster will do — the values a floe reads are the ones the
          # cluster settled on, not the ones the harness typed.
          cluster = {
            network.serviceSubnet = "10.96.0.0/12";
            provisionerOut.publishesGatewayPorts = publishesGatewayPorts;
          };
        })
        (stubClusterFold publishesGatewayPorts)
        {
          floeModules.gateway = import ../../floes/cluster/gateway/modular.nix;
          floeModules.cert-manager = stubCertManager;
          floes.gateway = settings // {
            enable = true;
          };
        }
      ];
    }).config;

  # Gateway's three assertions, isolated from whatever else each harness's
  # module list contributes — the old shape writes them at cluster scope, where
  # `capabilities.nix` and `prerequisites.nix` write too, so the two sides'
  # `assertions` are not comparable whole. All three name the option path they
  # are about, so the filter is the floe's own name rather than a positional
  # guess, and `testGatewayContributesThreeAssertions` below pins that it
  # selects all three rather than quietly selecting none.
  gatewayAssertions =
    assertions: map (a: a.message) (builtins.filter (a: lib.hasInfix "gateway" a.message) assertions);

  # --- the scenarios --------------------------------------------------------
  #
  # Gateway's body is almost all conditional, so one scenario proves little.
  # These three between them take every branch that changes a resource:
  # listeners with and without TLS, the NodePort path, and the internal tier's
  # extra Gateway and pinned-ClusterIP Service.
  scenarios = {
    basic = {
      settings = { };
    };

    tlsAndInternalNetbird = {
      settings = {
        tls = {
          enable = true;
          domain = "test.local";
        };
        internal = {
          enable = true;
          exposureMode = "netbird";
          clusterIPAddress = "10.96.0.250";
          domain = "internal.test.local";
        };
        internalHostnames = [
          "b.internal.test.local"
          "a.internal.test.local"
        ];
      };
    };

    nodePortWithTls = {
      publishesGatewayPorts = false;
      settings = {
        tls = {
          enable = true;
          domain = "test.local";
        };
        tls.passthrough.enable = true;
      };
    };
  };

  # Each scenario compared on every channel gateway writes. Built rather than
  # hand-listed so adding a scenario cannot silently skip a channel — the thing
  # a hand-written table gets wrong first.
  compareGateway =
    scenarioName: scenario:
    let
      o = oldGateway scenario;
      n = newGateway scenario;
      oldFloe = o.floes.gateway;
      newFloe = n.floes.gateway;

      # `<floe>.<channel>` in both shapes: the port moved the write from
      # `floes.gateway.<x>` to `<x>`, and the value should not have moved.
      ownChannels = {
        bundles = [
          newFloe.bundles
          oldFloe.bundles
        ];
        images = [
          newFloe.images
          oldFloe.images
        ];
        network = [
          newFloe.network
          oldFloe.network
        ];
        namespace = [
          newFloe.namespace
          oldFloe.namespace
        ];
        imagesComplete = [
          newFloe.imagesComplete
          oldFloe.imagesComplete
        ];
        exports = [
          newFloe.exports
          oldFloe.exports
        ];
        capabilities = [
          newFloe.capabilities
          oldFloe.capabilities
        ];
        driftExpected = [
          newFloe.drift.expected
          oldFloe.drift.expected
        ];
        lint = [
          newFloe.lint
          oldFloe.lint
        ];
        verify = [
          newFloe.verify
          oldFloe.verify
        ];
      };

      # `cluster.<channel>` in the old shape, folded from `<floe>.<channel>` in
      # the new one. The claim is about what the *cluster* ends up with, so
      # both sides are read off the cluster.
      foldedChannels = {
        clusterIngress = [
          n.cluster.ingress
          o.cluster.ingress
        ];
        clusterPrerequisites = [
          n.cluster.prerequisites
          o.cluster.prerequisites
        ];
      };

      assertionChannel.assertions = [
        (gatewayAssertions newFloe.assertions)
        (gatewayAssertions o.assertions)
      ];

      all = ownChannels // foldedChannels // assertionChannel;
    in
    lib.mapAttrs' (channel: pair: {
      name = "testGateway${lib.toUpper (lib.substring 0 1 scenarioName)}${
        lib.substring 1 (-1) scenarioName
      }_${channel}";
      value = {
        expr = builtins.elemAt pair 0;
        expected = builtins.elemAt pair 1;
      };
    }) all;

  gatewayTests = lib.foldl' (acc: n: acc // n) { } (lib.mapAttrsToList compareGateway scenarios);

  # A scenario that compared two empty attrsets on every channel would pass
  # vacuously. Pin that the interesting one actually produced the resources
  # the branches are there to produce.
  richest = (newGateway scenarios.tlsAndInternalNetbird).floes.gateway;
in
lib.runTests (
  {

    testBundlesAreIdentical = {
      expr = new.bundles;
      expected = old.bundles;
    };

    testImagesAreIdentical = {
      expr = new.images;
      expected = old.images;
    };

    testNetworkIsIdentical = {
      expr = new.network;
      expected = old.network;
    };

    testNamespaceIsIdentical = {
      expr = new.namespace;
      expected = old.namespace;
    };

    testImagesCompleteIsIdentical = {
      expr = new.imagesComplete;
      expected = old.imagesComplete;
    };

    # Exports minus the function, which is compared separately below.
    testValueExportsAreIdentical = {
      expr = removeAttrs new.exports [ "mkPatches" ];
      expected = removeAttrs old.exports [ "mkPatches" ];
    };

    testTheExportedFunctionStillBehavesTheSame = {
      expr = new.exports.mkPatches sampleWorkload;
      expected = old.exports.mkPatches sampleWorkload;
    };

    # And that it is not vacuously equal because both return nothing.
    testTheExportedFunctionProducesSomething = {
      expr = builtins.length (new.exports.mkPatches sampleWorkload);
      expected = 1;
    };

    # --- gateway, non-vacuity ------------------------------------------------

    # `tls.enable`'s default reads `peers.cert-manager.issuance`, and it is an
    # option default, so it is forced before the floe's own `config` runs.
    # This is the `gatewayOptions` pattern the spike proved on synthetic floes,
    # now on the floe that actually needs it.
    testGatewayReadsAPeerAtOptionDefaultTime = {
      expr =
        (newGateway {
          settings.tls.domain = "test.local";
        }).floes.gateway.exports.terminatingListenerName;
      expected = "https";
    };

    # And that the read is what decided it: no issuer, no HTTPS listener.
    testGatewayWithoutThePeerHasNoTlsListener = {
      expr =
        (lib.evalModules {
          modules = [
            (registry.mkRegistryModule {
              lab = gatewayLab;
              args = gatewayArgs;
              cluster.provisionerOut.publishesGatewayPorts = true;
            })
            {
              floeModules.gateway = import ../../floes/cluster/gateway/modular.nix;
              floes.gateway.enable = true;
            }
          ];
        }).config.floes.gateway.exports.terminatingListenerName;
      expected = "http";
    };

    testTheRichestScenarioProducedTheInternalGateway = {
      expr = lib.attrNames richest.bundles.gateway.resources;
      expected = [
        "default-gateway"
        "internal-gateway"
        "traefik-internal"
      ];
    };

    testTheRichestScenarioProducedThePrerequisite = {
      expr = lib.attrNames richest.prerequisites;
      expected = [ "gateway-api-crds" ];
    };

    testGatewayAssertionsAreNotEmpty = {
      expr = builtins.length richest.assertions;
      expected = 3;
    };

    # The `_assertions` comparisons above filter by message. Two empty lists
    # compare equal, so pin that the filter selects gateway's three.
    testGatewayContributesThreeAssertions = {
      expr = builtins.length (gatewayAssertions richest.assertions);
      expected = 3;
    };
  }
  // gatewayTests
)
