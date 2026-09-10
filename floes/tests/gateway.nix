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
    };
  };

  tls = support.evalFloe {
    name = "gateway";
    inputs = {
      chart = "/dev/null";
      tlsEnable = true;
    };
  };

  # The same floe on a cluster where nothing assigns LoadBalancer addresses.
  # Only that one field of the cluster differs — the inputs are `plain`'s.
  onNodePorts = support.evalFloe {
    name = "gateway";
    inputs = {
      chart = "/dev/null";
    };
    stubValues.cluster.assignsLoadBalancers = false;
  };

  listeners = r: map (l: l.name) r.bundles.gateway.resources.default-gateway.spec.listeners;

  traefikValues = r: r.bundles.controller.helmCharts.traefik.values;
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
      "stub.test"
      "*.stub.test"
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

  # ---- reached by NodePort ------------------------------------------------
  #
  # k3s ships ServiceLB and binds the node's own 80 and 443, so a LoadBalancer
  # Service is reachable at the node's name. Nothing else does: it stays
  # Pending forever, port 80 of the node answers nothing, and neither is a
  # failure anything reports.
  #
  # Both sides are pinned because only having the second would let the
  # NodePort become unconditional without a test moving.

  testOnAClusterWithServiceLbTheServiceKeepsItsDefault = {
    expr = (traefikValues plain).service or null;
    expected = null;
  };

  testWithoutOneTheGatewayAsksForANodePort = {
    expr = {
      inherit ((traefikValues onNodePorts).service) type;
      http = (traefikValues onNodePorts).ports.web.nodePort;
      https = (traefikValues onNodePorts).ports.websecure.nodePort;
    };
    expected = {
      type = "NodePort";
      # One value, in the distribution: the provisioner answers `edge.httpPort`
      # from the same attrset, so what the proxy dials and what the gateway
      # binds cannot drift.
      http = 30080;
      https = 30443;
    };
  };

  # An address is the right thing to wait for when something assigns one. A
  # Gateway fronted by a NodePort never gets one, so waiting for it waits out
  # the full timeout on a gateway that has been serving the whole time —
  # ten minutes of a lab looking hung, then a failure naming the wrong thing.
  testTheProbeWaitsForWhatCanActuallyArrive = {
    expr = {
      withServiceLb = plain.bundles.gateway.ready.kind;
      onNodePorts = onNodePorts.bundles.gateway.ready.kind;
      condition = onNodePorts.bundles.gateway.ready.condition or null;
    };
    expected = {
      withServiceLb = "jsonpath";
      onNodePorts = "condition";
      condition = "Programmed";
    };
  };
}
