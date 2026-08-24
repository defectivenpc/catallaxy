# Does porting a floe to the interface change what it produces?
#
# `floes/cluster/reloader/default.nix` and `.../modular.nix` are the same floe
# written both ways. Rendering is a pure function of the bundle data, so if the
# two produce equal `bundles`, `images`, `network` and `exports`, they render
# identical manifests — which is what the digest fixtures would otherwise have
# to prove through the whole pipeline.
#
# Asserted field by field rather than as one big equality, because a single
# `expected = { ... }` that fails tells you only that something moved.
{ lib, pkgs }:

let
  inherit (import ../floe { inherit lib; }) evalFloe;

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
  registry = import ../floe/registry.nix {
    inherit lib;
    modulesPath = ../../modules;
  };

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
in
lib.runTests {

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
}
