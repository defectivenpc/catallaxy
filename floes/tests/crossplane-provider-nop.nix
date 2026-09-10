# crossplane-provider-nop, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe { name = "crossplane-provider-nop"; };

  provider = r.bundles.provider.resources.provider;
  provided = r.provides.resourceProvider or { };
in
lib.runTests {

  testRendersSomething = {
    expr = r.bundles != { };
    expected = true;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  # `pkg.crossplane.io/v1`, read off the pinned CRD rather than recalled.
  testItAppliesTheKindTheControlPlaneAccepts = {
    expr = "${provider.apiVersion}/${provider.kind}";
    expected = "pkg.crossplane.io/v1/Provider";
  };

  # Crossplane pulls the package itself, so no pod spec here names it and the
  # image scrape cannot find it. Declared anyway: an operator mirroring this
  # lab into an airgap needs it, and the gate permits a declaration with no
  # rendered counterpart.
  testThePackageIsDeclaredAsAnImage = {
    expr = r.bundles.provider.images.provider.repository;
    expected = "crossplane-contrib/provider-nop";
  };

  testThePackageIsWhatTheProviderInstalls = {
    expr = provider.spec.package;
    expected = "ghcr.io/crossplane-contrib/provider-nop:v0.4.0";
  };

  # Installed means the package was pulled; its CRDs are registered only once
  # the revision is healthy. Waiting on the wrong one lets a consumer apply a
  # NopResource the API server has never heard of.
  testItWaitsForHealthyNotInstalled = {
    expr = {
      inherit (r.bundles.provider.ready) condition resource;
    };
    expected = {
      condition = "Healthy";

      # Short kind, not `provider.pkg.crossplane.io`: `cata lab lint` matches
      # a probe's target against the rendered object's normalised kind, and a
      # qualified one never matches — the probe would block to its timeout.
      resource = "provider/provider-nop";
    };
  };

  # The kinds are the whole point of requiring a provider rather than the
  # control plane: they arrive when it installs, not when it is applied.
  testItNamesTheKindsItBrings = {
    expr = provided.crdKinds or [ ];
    expected = [ "nop.crossplane.io/NopResource" ];
  };
}
