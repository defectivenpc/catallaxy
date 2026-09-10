# cert-manager, alone.
#
# The claim worth pinning here is the split: two provides, backed by
# different bundles, which is half of what removes the cycle this floe used
# to be in with trust-manager.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "cert-manager";
    inputs.chart = "/dev/null";
  };
in
lib.runTests {

  testWebhookAndIssuanceAreSeparateProvides = {
    expr = lib.attrNames r.provides;
    expected = [
      "issuance"
      "webhook"
    ];
  };

  # Backed by different bundles, which is the whole point: a consumer that
  # only needs the CRD installed waits for the chart, and one that needs a
  # signature waits for the issuer.
  testTheTwoAreBackedSeparately = {
    expr = r.component.backs;
    expected = {
      webhook = [ "cert-manager" ];
      issuance = [ "issuers" ];
    };
  };

  # The issuers cannot be applied before the webhook admits them.
  testIssuersFollowTheWebhook = {
    expr = r.bundles.issuers.needs;
    expected = [ "cert-manager" ];
  };

  # A lab CA is in nobody's trust store, and a consumer that cares has to be
  # able to ask rather than assume.
  testTheLabCAIsNotPublic = {
    expr = r.provides.issuance.publicIssuer;
    expected = false;
  };

  # The chart installs the CRDs, so eval cannot see them in `resources`;
  # declaring them is what lets a consumer's Certificate wait for the kind.
  testChartInstalledCrdsAreDeclared = {
    expr = lib.elem "cert-manager.io/Certificate" r.bundles.cert-manager.crds;
    expected = true;
  };

  # `namespaces` is the synthetic bundle the cluster renders from every
  # `createNamespaces`, so it is first wherever a floe creates one.
  testWaveOrder = {
    expr = r.waves;
    expected = [
      [ "namespaces" ]
      [ "cert-manager/cert-manager" ]
      [ "cert-manager/issuers" ]
    ];
  };
}
