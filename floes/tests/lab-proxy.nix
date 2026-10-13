# lab-proxy, alone.
#
# The haproxy config is the thing worth pinning, because every mistake in it
# is a timeout rather than an error: a backend nobody can resolve, a Host
# match that misses because the client sent a port, a redirect that keeps one.
#
# What it routes is a fan-in from the clusters, so the shape of that is pinned
# where the clusters are — the cli-config snapshots and
# `nix/checks/lab-scope.nix`. Here there is one contributor, which is enough
# to pin what a contribution turns into.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  linkWith =
    args:
    (support.evalFloe (
      {
        name = "lab-proxy";
        inputs = args.inputs or { };

        stubValues = {
          zone.zone = "example.test";
        }
        // (args.stubValues or { });
      }
      // removeAttrs args [
        "inputs"
        "stubValues"
      ]
    )).link;

  proxyWith = args: (linkWith args).provides.lab-proxy.service;
  routedWith = args: (linkWith args).out."catallaxy.routedHosts".lab-proxy;

  # The ports are the lab's allocated slot, not numbers chosen here: the floe
  # reads them off `lib/allocation.nix` from the lab name on `LAB_NETWORK`, so
  # a case naming a literal would be re-deriving the scheme.
  allocation = support.catallaxy.allocationFor "example";

  configOf = svc: svc.volumes."/usr/local/etc/haproxy/haproxy.cfg".content;

  tls = proxyWith { };
in
lib.runTests {

  # The backend is the collected cluster's, verbatim. It is a container name
  # and nothing but the thing that created the cluster knows it — the proxy
  # used to read it off `lab.edges`, which the lab filled from the descriptor,
  # which the provisioner filled. Two copies of one string, and the one the
  # proxy dialled was not the one `verify` probed.
  testItDialsTheAddressTheClusterGave = {
    expr = lib.hasInfix "server srv1 k3d-stub-server-0:443 ssl verify none" (configOf tls);
    expected = true;
  };

  # One backend per contributor, named after it, and a `use_backend` per
  # hostname that contributor claimed.
  testOneBackendPerClusterAndOneRoutePerHostname = {
    expr = {
      backend = lib.hasInfix "backend bk_http_stub-exposure" (configOf tls);
      route = lib.hasInfix "use_backend bk_http_stub-exposure if {" (configOf tls);
    };
    expected = {
      backend = true;
      route = true;
    };
  };

  # And it says so in the document `cata lab verify` probes, keyed the same
  # way the backends are. One expression behind both, so a hostname cannot be
  # probed through a backend that was never written — which is what `verify`
  # did for `minimal.local`, a lab with a routed workload and no ingress at
  # all: `modules/lab/out.nix` read the clusters' exposures directly and
  # listed hostnames nothing answered for.
  testItSaysWhatItRoutes = {
    expr = routedWith { };
    expected.stub-exposure = [ "app.stub.test" ];
  };

  # A cluster the proxy has no backend for is not in the map either, for the
  # same reason it has no `use_backend` line.
  testWithNothingExportedItRoutesNothing = {
    expr = routedWith { without = [ "exposure" ]; };
    expected = { };
  };

  # `field(1,:)` drops the port before matching. A client reaching a lab on
  # anything but 80/443 sends `Host: name:8443`, which an exact match on the
  # bare name misses — and the symptom is a 503 from the ingress rather than
  # anything naming the header. Non-default ports are the normal case as soon
  # as a second lab shares the host.
  testItMatchesTheHostHeaderWithThePortDropped = {
    expr = lib.hasInfix "{ req.hdr(host),field(1,:) -i app.stub.test }" (configOf tls);
    expected = true;
  };

  # `init-addr none` with a resolver, not resolution at startup: the proxy
  # comes up before the cluster it points at exists, and HAProxy refuses to
  # start on a server name it cannot resolve.
  testItStartsBeforeItsBackendsExist = {
    expr = {
      resolver = lib.hasInfix "resolvers docker" (configOf tls);
      deferred = lib.hasInfix "init-addr none" (configOf tls);
    };
    expected = {
      resolver = true;
      deferred = true;
    };
  };

  # Plain HTTP redirects to the *bare* host rather than with `redirect scheme
  # https`, which keeps whatever port the client used and would send it to
  # HTTPS on the HTTP port.
  testTheRedirectDropsThePort = {
    expr = lib.hasInfix "redirect location https://%[req.hdr(host),field(1,:)]%[path]" (configOf tls);
    expected = true;
  };

  # Published twice on purpose. Loopback is where a human reaches it; the
  # bridge gateway is what the zone's records answer, and so what everything
  # inside the lab reaches it on. Only the second is reachable from a pod, and
  # only the first from a browser with no DNS setup.
  testItIsPublishedOnLoopbackAndOnTheBridge = {
    expr = tls.ports;
    expected = [
      "127.0.0.1:${toString allocation.proxyHttp}:80"
      "172.20.0.1:80:80"
      "127.0.0.1:${toString allocation.proxyHttps}:443"
      "172.20.0.1:443:443"
    ];
  };

  # A port said explicitly wins over the allocation. The reason it is sayable
  # at all: an allocated port looks free in a table of registered names and
  # may not be, and `nix/checks/lab-edge.nix` moves one to stand two labs up
  # beside each other.
  testAnExplicitPortWinsOverTheAllocation = {
    expr = (proxyWith { inputs.httpPort = 8091; }).ports;
    expected = [
      "127.0.0.1:8091:80"
      "172.20.0.1:80:80"
      "127.0.0.1:${toString allocation.proxyHttps}:443"
      "172.20.0.1:443:443"
    ];
  };

  # With no root in the link there is no TLS: no https listener to bind,
  # neither port published, and the backend dialled in plaintext on the port
  # the cluster gave for it.
  #
  # Said by the absence of a `lab-ca`, not by a flag. It was a `tlsEnable`
  # input the lab filled from an option defaulting to true that no lab set,
  # while the step minting the certificate was gated on the same option
  # elsewhere.
  testWithNoRootNothingBindsOr443 =
    let
      plain = proxyWith { without = [ "labCa" ]; };
    in
    {
      expr = {
        inherit (plain) ports extraMounts;
        backend = lib.hasInfix "server srv1 k3d-stub-server-0:80 " (configOf plain);
        frontend = lib.hasInfix "bind *:443" (configOf plain);
      };
      expected = {
        ports = [
          "127.0.0.1:${toString allocation.proxyHttp}:80"
          "172.20.0.1:80:80"
        ];
        extraMounts = [ ];
        backend = true;
        frontend = false;
      };
    };

  # The key is mounted from the host and not carried in the document, because
  # `cert-generate` writes it at `cata lab up` and a private key in the store
  # is a private key anyone on the machine can read.
  testTheCertificateIsMountedNotRendered = {
    expr = tls.extraMounts;
    expected = [
      {
        host = "{{STATE_DIR}}/proxy/lab.pem";
        container = "/etc/haproxy/certs/lab.pem";
      }
    ];
  };

  # A lab that fronts nothing still starts: the config is well-formed with no
  # routes, which is what a lab whose every cluster is its own edge renders.
  testWithNothingExportedItStillStarts =
    let
      empty = proxyWith { without = [ "exposure" ]; };
    in
    {
      expr = {
        listener = lib.hasInfix "frontend ft_https" (configOf empty);
        backends = lib.hasInfix "backend bk_http_" (configOf empty);
      };
      expected = {
        listener = true;
        backends = false;
      };
    };

  # And the one combination that is refused: hostnames the lab is asked to
  # answer for, from a cluster whose provisioner gave no address. Every
  # request would reach the default backend and time out, so this is an eval
  # failure naming the cluster rather than a config that starts.
  testFrontingAClusterWithNoAddressIsRefused = {
    expr =
      (builtins.tryEval (builtins.deepSeq (proxyWith { stubValues.exposure.edge = null; }) "evaluated"))
      .success;
    expected = false;
  };
}
