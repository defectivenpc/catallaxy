# lab-egress, alone.
#
# The first floe to provide a `HOST_SERVICE`: a container the lab runs on
# the operator's machine rather than anything installed into a cluster. What is
# worth pinning is the shape of that output, because the CLI starts it and a
# field it cannot read is a service that never comes up.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  r = support.evalFloe {
    name = "lab-egress";
    stubValues.zone.zone = "example.test";
  };

  # The ports are the lab's allocated slot, not numbers chosen here: the floe
  # reads them off `lib/allocation.nix` from the lab name on `LAB_NETWORK`, so
  # a case naming a literal would be re-deriving the scheme.
  allocation = support.catallaxy.allocationFor "example";

  service = r.link.provides.lab-egress.service;
in
lib.runTests {

  # The record `setup-services` starts. Published on loopback, joined to the
  # lab's network so it can reach the clusters on it, and resolving through
  # the lab's own DNS so a request for a lab hostname gets the lab's answer.
  testItEmitsTheRecordTheCliStarts = {
    expr = {
      inherit (service)
        container
        ports
        networks
        dnsContainers
        ;
    };
    expected = {
      container = "catallaxy-example-egress";
      ports = [ "127.0.0.1:${toString allocation.egress}:8888" ];
      networks = [ "example" ];
      dnsContainers = [ "catallaxy-example-dns" ];
    };
  };

  # A lab with no resolver of its own leaves this empty rather than naming a
  # container that does not exist — which docker rejects outright, so the whole
  # service fails to start rather than resolving badly.
  testWithNoResolverItNamesNone = {
    expr =
      (support.evalFloe {
        name = "lab-egress";
        stubValues.zone.zone = "example.test";
        without = [ "resolver" ];
      }).link.provides.lab-egress.service.dnsContainers;
    expected = [ ];
  };

  # The config is inline content and not a path, because a floe's output is
  # inert data: the CLI writes the file. Keyed by where it lands *inside* the
  # container, which is the only address a mount has that the floe knows.
  testTheConfigIsContentAtAPathInsideTheContainer = {
    expr = {
      path = lib.head (lib.attrNames service.volumes);
      hasPort = lib.hasInfix "Port 8888" service.volumes."/etc/tinyproxy/tinyproxy.conf".content;
    };
    expected = {
      path = "/etc/tinyproxy/tinyproxy.conf";
      hasPort = true;
    };
  };

  # Its whole interface: the container it runs, and the one thing it cannot
  # know about itself. A host floe answers `HOST_SERVICE` and nothing else —
  # asking it to require a *cluster* would be inventing a dependency to
  # satisfy a check, and the network is not that: it is which docker network
  # this container is on.
  #
  # `HOST_SERVICE` rather than a `catallaxy.hostService` output, because the
  # fan-in is `lab-services`' and a floe cannot collect an output kind. The
  # suite used to assert this floe provided nothing at all.
  testItRunsAContainerAndJoinsTheLabsNetwork = {
    expr = {
      requires = lib.attrNames r.def.requires;
      provides = lib.attrNames r.def.provides;
      out = lib.attrNames r.def.out;
    };
    expected = {
      requires = [
        "network"
        "zone"
      ];
      provides = [ "service" ];
      out = [ ];
    };
  };
}
