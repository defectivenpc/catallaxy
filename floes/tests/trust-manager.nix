# trust-manager, alone.
#
# The claim worth pinning is the direction of the edge to cert-manager. In
# the old tree cert-manager emitted the Bundle CRs and read trust-manager's
# export to know whether it could, so the two were mutually dependent. Here
# trust-manager reads cert-manager and cert-manager reads nothing.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "trust-manager";
    inputs.chart = "/dev/null";
  };

  bundle = r.bundles.bundles.resources;
in
lib.runTests {

  testDependsOnCertManagerRatherThanTheReverse = {
    expr =
      lib.attrNames
        (import ../cluster/trust-manager {
          inherit lib pkgs;
          catallaxy = support.catallaxy;
          inherit (support.catallaxy) floe sigs kinds;
        }).requires;
    expected = [
      "cluster"
      "issuance"
      "webhook"
    ];
  };

  # It distributes the CA the issuer signs from, which it learns through the
  # signature rather than by knowing cert-manager's Secret naming scheme.
  testBundleSourcesTheIssuersCA = {
    expr = (lib.head bundle.ca-bundle.spec.sources).secret;
    expected = {
      name = "stub-ca-secret";
      key = "tls.crt";
    };
  };

  # Every namespace: which workloads need the lab CA is not knowable here,
  # and an empty selector is cheaper than being told.
  testTheBundleTargetsEveryNamespace = {
    expr = bundle.ca-bundle.spec.target.namespaceSelector;
    expected = { };
  };

  # Some consumers can only mount a CA from a Secret, so both shapes ship.
  testItAlsoDistributesASecret = {
    expr = lib.attrNames bundle;
    expected = [
      "ca-bundle"
      "ca-bundle-secret"
    ];
  };

  testTheBundlesFollowTheController = {
    expr = r.bundles.bundles.needs;
    expected = [ "trust-manager" ];
  };
}
