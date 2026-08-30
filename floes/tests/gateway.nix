# gateway, alone.
#
# Two claims worth pinning: the listener a consumer attaches to follows
# whether TLS is on, and the fan-in gives the gateway something it can check
# that no consumer could — that a route's hostname is inside its zone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  plain = support.evalFloe {
    name = "gateway";
    inputs = {
      chart = "/dev/null";
      baseDomain = "lab.test";
    };
  };

  tls = support.evalFloe {
    name = "gateway";
    inputs = {
      chart = "/dev/null";
      baseDomain = "lab.test";
      tlsEnable = true;
    };
  };

  listeners = r: map (l: l.name) r.bundles.gateway.resources.default-gateway.spec.listeners;
in
lib.runTests {

  # With TLS off there is one listener and a consumer attaches to it.
  testPlainHasOneListener = {
    expr = listeners plain;
    expected = [ "http" ];
  };

  testPlainAttachesToHttp = {
    expr = plain.provides.gateway.parentRef.sectionName;
    expected = "http";
  };

  # With TLS on, plaintext exists only to be redirected, so the parentRef a
  # consumer is handed has to move with it. Deriving it is what keeps a
  # consumer from spelling "https" and being wrong in the other lab.
  testTlsAddsAListenerAndMovesTheAttachment = {
    expr = {
      listeners = listeners tls;
      attachesTo = tls.provides.gateway.parentRef.sectionName;
    };
    expected = {
      listeners = [
        "http"
        "https"
      ];
      attachesTo = "https";
    };
  };

  # One wildcard for the zone, so adding a route does not reissue the
  # certificate.
  testTlsCertificateCoversTheZone = {
    expr = tls.bundles.gateway.resources.gateway-tls.spec.dnsNames;
    expected = [
      "lab.test"
      "*.lab.test"
    ];
  };

  # Signed by whatever provided X509_ISSUANCE — the gateway never spells an
  # issuer's name.
  testTheCertificateUsesTheProvidedIssuer = {
    expr = tls.bundles.gateway.resources.gateway-tls.spec.issuerRef;
    expected = {
      name = "stub-ca";
      kind = "ClusterIssuer";
    };
  };

  testPlainRendersNoCertificate = {
    expr = lib.attrNames plain.bundles.gateway.resources;
    expected = [ "default-gateway" ];
  };

  testTheGatewayFollowsItsController = {
    expr = plain.bundles.gateway.needs;
    expected = [ "controller" ];
  };
}
