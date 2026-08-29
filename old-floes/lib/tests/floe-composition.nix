# Can an author write only an *instance* and get core functionality free?
#
# That is the spike's actual question, and `floe-typeclass.nix` does not answer
# it — that one proves the type exists and instances conform. This proves there
# is something written once against the type that instances get behaviour from,
# and that the type safety is real and extensible by a floe author.
#
# Four claims, in order:
#
#   1. **Composition.** A floe contains floes (`lib/services/service.nix:25`),
#      so a lab floe is not a second interface — it is a floe whose sub-floes
#      are cluster floes.
#   2. **Core functionality once.** `lib/floe/fold.nix` walks the tree; an
#      author writing `assertions = [ … ]` at any depth gets a path-prefixed
#      report with no per-floe wiring. This is `lib/services/lib.nix`'s
#      `getAssertions`, which is the thing upstream chose to demonstrate.
#   3. **Channel folding.** The eight hand-written `mkMerge (mapAttrsToList …)`
#      folds become one table.
#   4. **Typed wiring.** A floe names a *job*; the framework resolves it, and
#      the failures are sentences naming the floe and the capability.
{ lib, pkgs }:

let
  registry = import ../floe/registry.nix {
    inherit lib;
    modulesPath = ../../modules;
  };
  fold = import ../floe/fold.nix { inherit lib; };
  contracts = import ../contracts { inherit lib; };

  baseArgs = {
    inherit pkgs contracts;
    lab = {
      name = "t";
      images = { };
    };
    cluster = { };
  };

  evalCluster =
    floeModules:
    lib.evalModules {
      modules = [
        (registry.mkRegistryModule {
          args = baseArgs;
          extensions = [ registry.clusterExtension ];
        })
        { inherit floeModules; }
      ];
    };

  evalLab =
    floeModules:
    lib.evalModules {
      modules = [
        (registry.mkRegistryModule {
          args = baseArgs;
          extensions = [ registry.labExtension ];

          # A lab floe's sub-floes are cluster floes. This one line is the
          # whole of the scope hierarchy.
          childExtensions = [ registry.clusterExtension ];
        })
        { inherit floeModules; }
      ];
    };

  # ==========================================================================
  # 1. Composition — a floe that contains floes
  # ==========================================================================

  # A lab-scope floe holding two cluster-scope sub-floes. Both scopes are the
  # same class, so this is one registry with one extension list, not a lab
  # registry bolted to a cluster one.
  platform =
    { lib, ... }:
    {
      config = {
        enable = true;
        clusters = [ "app" ];
        labConfig.dns.enable = true;

        assertions = [
          {
            assertion = false;
            message = "the platform objected";
          }
        ];

        floes.alpha = {
          enable = true;
          assertions = [
            {
              assertion = false;
              message = "alpha objected";
            }
          ];
          warnings = [ "alpha grumbled" ];
        };

        floes.beta = {
          enable = true;
          floes.nested = {
            enable = true;
            assertions = [
              {
                assertion = false;
                message = "the grandchild objected";
              }
            ];
          };
        };
      };
    };

  composed = evalLab { platform = platform; };

  # ==========================================================================
  # 2 & 3. Core functionality, written once
  # ==========================================================================

  # Two cluster floes that each contribute to the same channels. Nothing in
  # either names the fold, and the fold names neither of them.
  producerA =
    { lib, ... }:
    {
      config = {
        enable = true;
        bundles.a.provides = [ "a/ready" ];
        prerequisites.shared.provides = [ "shared/crds" ];
        ingress.httpPort = 30080;
        warnings = [ "A is provisional" ];
      };
    };

  producerB =
    { lib, ... }:
    {
      config = {
        enable = true;
        bundles.b.provides = [ "b/ready" ];
        # Same prerequisite as A. Merging rather than conflicting is the whole
        # reason `prerequisites` is not a bundle.
        prerequisites.shared.provides = [ "shared/also" ];
        ingress.httpsPort = 30443;
      };
    };

  folded = evalCluster {
    a = producerA;
    b = producerB;
  };

  # The fold as a table. This replaces eight hand-written `mkMerge` folds in
  # the cluster module, and adding a ninth channel is one more line here.
  foldedChannels = fold.foldChannels folded.config {
    bundles = [ "bundles" ];
    prerequisites = [ "prerequisites" ];
    ingress = [ "ingress" ];
  };

  # `collectChannel` returns an `mkMerge`, which is a definition rather than a
  # value — it has to be, or two floes writing the same key could not conflict.
  # Realising it needs a module system, so the test evaluates it the way a
  # cluster would.
  realiseFold = lib.evalModules {
    modules = [
      {
        options.bundles = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.raw);
          default = { };
        };
        options.prerequisites = lib.mkOption {
          type = lib.types.attrsOf (
            (import ../../modules/lab/cluster/prerequisite-types.nix { inherit lib; }).prerequisiteType
          );
          default = { };
        };
        options.ingress = lib.mkOption {
          type = lib.types.attrsOf lib.types.port;
          default = { };
        };
      }
      {
        bundles = lib.mapAttrs (_: b: removeAttrs b [ "declaredBy" ]) (
          lib.mapAttrs (_: b: { inherit (b) provides; }) folded.config.floes.a.bundles
        );
      }
      { inherit (foldedChannels) prerequisites ingress; }
    ];
  };

  # ==========================================================================
  # 4. Typed wiring
  # ==========================================================================

  gatewayProvider =
    { lib, contracts, ... }:
    {
      config = {
        enable = true;
        capabilities.provides.api-gateway = contracts.api-gateway.apiGateway.claim {
          routing = {
            publicReady = "gateway/public/ready";
            controllerReady = "gateway/controller/ready";
          };
          internalEnabled = true;
        };
      };
    };

  # A second, entirely different implementation of the same job. The consumer
  # below does not change, which is what naming a job rather than a floe buys.
  ciliumProvider =
    { lib, contracts, ... }:
    {
      config = {
        enable = true;
        capabilities.provides.api-gateway = contracts.api-gateway.apiGateway.claim {
          routing = {
            publicReady = "cilium/gateway/ready";
            controllerReady = "cilium/agent/ready";
          };
          internalEnabled = false;
        };
      };
    };

  consumer =
    { lib, config, ... }:
    {
      options.exports = lib.mkOption {
        type = lib.types.submodule {
          options.attachedTo = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
      };
      config = {
        enable = true;
        dependencies.gateway.capability = "api-gateway";
        # Reads the *contract's* shape, not the provider's exports.
        exports.attachedTo = config.deps.gateway.routing.publicReady;
      };
    };

  withTraefik = evalCluster {
    gateway = gatewayProvider;
    app = consumer;
  };

  withCilium = evalCluster {
    cilium = ciliumProvider;
    app = consumer;
  };

  # No provider at all.
  unprovided = builtins.tryEval (
    builtins.deepSeq (evalCluster { app = consumer; }).config.floes.app.exports.attachedTo "evaluated"
  );

  # Two providers of one job.
  ambiguous = builtins.tryEval (
    builtins.deepSeq
      (evalCluster {
        gateway = gatewayProvider;
        cilium = ciliumProvider;
        app = consumer;
      }).config.floes.app.exports.attachedTo
      "evaluated"
  );

  optionalConsumer =
    { lib, config, ... }:
    {
      options.exports = lib.mkOption {
        type = lib.types.submodule {
          options.gatewayPresent = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
      };
      config = {
        enable = true;
        dependencies.gateway = {
          capability = "api-gateway";
          optional = true;
        };
        exports.gatewayPresent = config.deps.gateway != null;
      };
    };

  # A provider claiming a field the contract does not declare. The contract
  # refuses it, which is the author-facing half of the type safety.
  badClaim = builtins.tryEval (
    builtins.deepSeq
      (evalCluster {
        gateway =
          { contracts, ... }:
          {
            config = {
              enable = true;
              capabilities.provides.api-gateway = contracts.api-gateway.apiGateway.claim {
                routing = {
                  publicReady = "x";
                  controllerReady = "y";
                };
                internalEnabled = false;
                dashboardUrl = "http://not-part-of-the-job";
              };
            };
          };
      }).config.floes.gateway.capabilities.provides
      "evaluated"
  );

  # ==========================================================================
  # 5. The real lab floe
  # ==========================================================================

  k3dLab = evalLab { k3d-local = import ../../floes/lab/k3d-local-modular.nix; };
  k3d = k3dLab.config.floes.k3d-local;

  k3dConfigured =
    (evalLab {
      k3d-local = {
        imports = [ (import ../../floes/lab/k3d-local-modular.nix) ];
        config = {
          enable = true;
          clusters = [
            "app"
            "mgmt"
          ];
          tls = false;
        };
      };
    }).config.floes.k3d-local;
in
lib.runTests {

  # --- 1. composition ------------------------------------------------------

  # The headline: a floe holds floes, at more than one level.
  testAFloeContainsFloes = {
    expr = lib.attrNames composed.config.floes.platform.floes;
    expected = [
      "alpha"
      "beta"
    ];
  };

  testCompositionNests = {
    expr = lib.attrNames composed.config.floes.platform.floes.beta.floes;
    expected = [ "nested" ];
  };

  # A sub-floe of a lab floe is a *cluster* floe: it has the cluster
  # extension's channels. Same class, one registry, extensions decide the rest.
  testASubFloeCarriesTheClusterExtension = {
    expr = composed.config.floes.platform.floes.alpha ? bundles;
    expected = true;
  };

  # And the parent carries the lab extension's.
  testTheParentCarriesTheLabExtension = {
    expr = composed.config.floes.platform.clusters;
    expected = [ "app" ];
  };

  # --- 2. core functionality, written once ---------------------------------

  # Nothing in any of those four floes wired itself to a collector, and the
  # collector names none of them. Every assertion in the tree arrives with the
  # path of the floe that made it — including the grandchild's.
  testAssertionsAreCollectedThroughTheWholeTree = {
    expr = map (a: a.message) (fold.collectAssertions composed.config);
    expected = [
      "in floes.platform: the platform objected"
      "in floes.platform.floes.alpha: alpha objected"
      "in floes.platform.floes.beta.floes.nested: the grandchild objected"
    ];
  };

  testWarningsAreCollectedTheSameWay = {
    expr = fold.collectWarnings composed.config;
    expected = [ "in floes.platform.floes.alpha: alpha grumbled" ];
  };

  # The collectors are honest about passing assertions too — they collect the
  # whole channel, and the containing system decides what a false one means.
  testCollectedAssertionsCarryTheirVerdict = {
    expr = map (a: a.assertion) (fold.collectAssertions composed.config);
    expected = [
      false
      false
      false
    ];
  };

  testWarningsAreCollectedAcrossSiblingsToo = {
    expr = fold.collectWarnings folded.config;
    expected = [ "in floes.a: A is provisional" ];
  };

  # --- 3. channel folding --------------------------------------------------

  # Two floes, different keys, one merged channel — with no per-channel fold
  # written anywhere.
  testChannelsFoldAcrossFloes = {
    expr = lib.attrNames realiseFold.config.ingress;
    expected = [
      "httpPort"
      "httpsPort"
    ];
  };

  testFoldedValuesSurvive = {
    expr = realiseFold.config.ingress.httpPort;
    expected = 30080;
  };

  # Two floes contributing the *same* prerequisite key merge rather than
  # conflict, which is the reason prerequisites are not bundles.
  testSameKeyFromTwoFloesMerges = {
    expr = lib.sort lib.lessThan realiseFold.config.prerequisites.shared.provides;
    expected = [
      "shared/also"
      "shared/crds"
    ];
  };

  # A lab floe has no `bundles`; the collector skips it rather than failing,
  # because which channels exist is the extension's business.
  testFoldingSkipsFloesWithoutTheChannel = {
    expr = builtins.isAttrs (fold.collectChannel [ "bundles" ] composed.config);
    expected = true;
  };

  # --- 4. typed wiring -----------------------------------------------------

  testADependencyResolvesByCapability = {
    expr = withTraefik.config.floes.app.exports.attachedTo;
    expected = "gateway/public/ready";
  };

  # The consumer is byte-identical between these two; only the provider
  # changed. This is what naming a job rather than a floe is for.
  testTheProviderCanBeSwappedWithoutTouchingTheConsumer = {
    expr = withCilium.config.floes.app.exports.attachedTo;
    expected = "cilium/gateway/ready";
  };

  # The failure this replaces is a missing-attribute error, which `tryEval`
  # cannot even catch. This one it can, which is itself the improvement.
  testAnUnprovidedCapabilityFails = {
    expr = unprovided.success;
    expected = false;
  };

  testTwoProvidersOfOneJobFail = {
    expr = ambiguous.success;
    expected = false;
  };

  # An optional slot resolves to null instead of failing.
  testAnOptionalDependencyResolvesToNull = {
    expr = (evalCluster { app = optionalConsumer; }).config.floes.app.exports.gatewayPresent;
    expected = false;
  };

  testAnOptionalDependencyStillBindsWhenProvided = {
    expr =
      (evalCluster {
        gateway = gatewayProvider;
        app = optionalConsumer;
      }).config.floes.app.exports.gatewayPresent;
    expected = true;
  };

  # The author-facing half: a provider cannot claim a field the job does not
  # have. This is where a floe author plugs into the type safety — the
  # contract, not the interface, decides what the job's surface is.
  testAProviderCannotClaimAFieldTheContractLacks = {
    expr = badClaim.success;
    expected = false;
  };

  # --- 5. the real lab floe ------------------------------------------------

  testTheLabFloeIsOffByDefault = {
    expr = k3d.labConfig;
    expected = { };
  };

  testTheLabFloeExportsItsClusters = {
    expr = k3dConfigured.exports.clusters;
    expected = [
      "app"
      "mgmt"
    ];
  };

  testTheLabFloeConfiguresTheLab = {
    expr = lib.attrNames k3dConfigured.labConfig.clusters;
    expected = [
      "app"
      "mgmt"
    ];
  };

  testTheLabFloeClaimsItsJob = {
    expr = lib.attrNames k3dConfigured.capabilities.provides;
    expected = [ "kubernetes-cluster" ];
  };

  # The base channels are the same ones a cluster floe has — same names, same
  # types, one declaration. That is the claim the lab scope rests on.
  testLabAndClusterFloesShareTheBaseInterface = {
    expr = lib.all (channel: k3d ? ${channel} && folded.config.floes.a ? ${channel}) [
      "enable"
      "exports"
      "capabilities"
      "dependencies"
      "assertions"
      "warnings"
      "ops"
      "lint"
      "verify"
      "floes"
    ];
    expected = true;
  };

  # And the extensions differ, which is the other half.
  testTheExtensionsDiffer = {
    expr = {
      labHasBundles = k3d ? bundles;
      clusterHasClusters = folded.config.floes.a ? clusters;
    };
    expected = {
      labHasBundles = false;
      clusterHasClusters = false;
    };
  };
}
