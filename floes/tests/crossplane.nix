# crossplane, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "crossplane";
    inputs.chart = "/dev/null";
    inputs.crds = "/dev/null";
  };

  provided = r.provides.controlPlane or { };
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

  # Two bundles for two readiness facts. A `Provider` can be applied once the
  # CRDs are established, which happens well before the controller is up; a
  # floe waiting for that provider to reconcile needs the second.
  testTheCrdsAreTheirOwnBundle = {
    expr = lib.sort (a: b: a < b) (lib.attrNames r.bundles);
    expected = [
      "crds"
      "crossplane"
    ];
  };

  testTheControllerFollowsTheCrds = {
    expr = r.bundles.crossplane.needs;
    expected = [ "crds" ];
  };

  # The chart ships no CRDs — not in `crds/`, not as templates — so this
  # bundle is their only source. If the chart ever starts shipping them, two
  # owners of one object make a re-apply fight itself.
  testTheCrdsComeFromThePin = {
    expr = r.bundles.crds.yamls;
    expected = [ "/dev/null" ];
  };

  # `pkg.crossplane.io/Provider` is the one a provider floe applies, so it is
  # the one whose absence would strand every provider.
  #
  # Declaring it is also all the ordering a provider needs: `elaborate.nix`
  # turns a bundle's `crds` into `kind:` provided names, so the provider's own
  # bundle lands after this one without either floe naming a token. That
  # derivation belongs to the elaborator and is pinned in
  # `lib/tests/manifest-autoedges.nix`; here the claim is just that the kind
  # is declared.
  testItRegistersTheProviderKind = {
    expr = lib.elem "pkg.crossplane.io/Provider" r.bundles.crds.crds;
    expected = true;
  };

  # A provider floe renders this kind and should not spell it: the control
  # plane names what it accepts.
  testItNamesTheProviderKindItAccepts = {
    expr = provided.providerKind or null;
    expected = "pkg.crossplane.io/Provider";
  };
}
