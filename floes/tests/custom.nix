# custom, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "custom";
    inputs = {
      name = "app";
      namespace = "app";
      servicePort = 8080;
    };
  };

  route = r.bundles.app.resources.route;
in
lib.runTests {
  # From the stub gateway's `baseDomain`, not spelled here. A lab that writes
  # its own zone into this floe has two places to change it.
  testTheHostnameComesFromTheGateway = {
    expr = r.provides.route.hostname;
    expected = "app.stub.test";
  };

  # The route attaches through the sealed API_GATEWAY value, so this floe
  # never names the gateway, its namespace or its listener.
  testItNeverSpellsTheGateway = {
    expr = route.spec.parentRefs;
    expected = [
      {
        name = "stub-gateway";
        namespace = "kube-system";
        sectionName = "https";
      }
    ];
  };

  testTheBackendDefaultsToTheAppName = {
    expr = (lib.head (lib.head route.spec.rules).backendRefs).name;
    expected = "app";
  };

  # One bundle named for the app, not for the floe: a lab instantiates this
  # once per app, and two instances must not collide on a bundle key.
  testTheBundleIsNamedForTheApp = {
    expr = lib.attrNames r.bundles;
    expected = [ "app" ];
  };

  # It is handed arbitrary resources and cannot enumerate what they pull.
  # Claiming otherwise would put a false claim in front of the gate that
  # checks image completeness.
  testItDoesNotClaimToKnowItsImages = {
    expr = r.component.imagesComplete;
    expected = false;
  };

  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
