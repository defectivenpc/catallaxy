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
    expr = route.spec.hostnames;
    expected = [ "app.stub.test" ];
  };

  # `kinds.mkRoute` refuses it at construction, so the eval trace names the
  # floe that asked rather than reporting, from the gateway, that some route
  # somewhere is wrong. A route on a host the gateway cannot serve attaches
  # happily and then serves nothing: the wildcard certificate does not cover
  # it and no DNS in the lab answers for it.
  testAHostnameOutsideTheZoneIsRefused = {
    expr =
      support.fails
        (support.evalFloe {
          name = "custom";
          inputs = {
            name = "app";
            namespace = "app";
            hostname = "app.somewhere-else.test";
          };
        }).bundles;
    expected = true;
  };

  # The paired positive. Without it the refusal above could pass because the
  # floe fails to evaluate for some unrelated reason, which is how five
  # refusals in nix/checks/secret-sharing.nix once passed for the wrong one.
  testAHostnameInsideTheZoneIsAccepted = {
    expr =
      (support.evalFloe {
        name = "custom";
        inputs = {
          name = "app";
          namespace = "app";
          hostname = "anything.stub.test";
        };
      }).bundles.app.resources.route.spec.hostnames;
    expected = [ "anything.stub.test" ];
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
