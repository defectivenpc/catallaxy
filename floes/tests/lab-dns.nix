# lab-dns, alone.
#
# The zone file is the thing worth pinning, because it is the one place a lab's
# routing becomes a DNS answer — and the wrong answer here is not an error. A
# record for a cluster the lab does not front resolves that hostname to a proxy
# with no backend for it, which is a timeout rather than a failure.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  linkWith =
    extra:
    (support.evalFloe (
      {
        name = "lab-dns";
        inputs = extra.inputs or { };

        stubValues = {
          zone.zone = "example.test";
        }
        // (extra.stubValues or { });
      }
      // removeAttrs extra [
        "inputs"
        "stubValues"
      ]
    )).link;

  dnsWith = extra: (linkWith extra).provides.lab-dns.service;

  # Its own output kind: running a container and contributing a step are two
  # declarations, so a resolver that touches nothing on the host emits no
  # `catallaxy.labSteps` at all rather than an empty one.
  stepsOf = extra: (linkWith extra).provides.lab-dns.step.steps;

  # A resolver with nothing exported to it. Its own case, and the one every
  # test below that is not about the fan-in wants: a record is a contribution,
  # so leaving the stub out is how a case says "no cluster said anything".
  fronting = dnsWith { };
  frontingNothing = dnsWith { without = [ "exposure" ]; };

  # Off the zone's provider, not chosen here. `lab-dns` publishes on the port
  # the zone names rather than taking one of its own — it was a `hostPort`
  # input beside a `lab.dns.port` that defaulted to it, which is one number a
  # lab could move in one place and not the other.
  inherit (support.stubs.zone.value) port;

  zoneOf = svc: svc.volumes."/storage/example.test.zone".content;

in
lib.runTests {

  # No wildcard, ever. It was a stand-in for not knowing which hostnames a
  # lab serves: it answered for the whole zone, and had to be suppressed
  # entirely whenever any cluster was its own edge, because otherwise it
  # answered for that cluster's names too and sent them to a proxy with no
  # backend. The list is collected now, so there is nothing to stand in for.
  #
  # How the fan-in across clusters composes is pinned where the clusters are —
  # `nix/checks/lab-scope.nix` and the cli-config snapshots. Here it is one
  # contributor, which is enough to pin what a contribution turns into.
  testItNeverAnswersWithAWildcard = {
    expr = {
      withAHost = lib.hasInfix "*   IN  A" (zoneOf fronting);
      withNone = lib.hasInfix "*   IN  A" (zoneOf frontingNothing);
    };
    expected = {
      withAHost = false;
      withNone = false;
    };
  };

  # One record per claimed hostname, pointing at the address inside the lab
  # network. The hostname arrives through the collection; nothing here was
  # handed a list.
  #
  # Written in full because the stub's hostname is in `stub.test` and this
  # zone is `example.test`, so the suffix the records are relative to does not
  # match. A name a lab is asked to answer for from outside its own zone is
  # emitted as written, which is the honest thing for a zone file to do with
  # it: `$ORIGIN` makes it `app.stub.test.example.test.`, visibly wrong,
  # rather than quietly answering for someone else's name.
  testItAnswersForWhatAClusterExported = {
    expr = lib.hasInfix "app.stub.test   IN  A   172.20.0.1" (zoneOf fronting);
    expected = true;
  };

  # A lab that fronts nothing answers for the zone itself and no more. The SOA
  # and NS are always there, because a zone without them is not a zone.
  testWithNothingExportedItStillServesTheZone = {
    expr =
      let
        zone = zoneOf frontingNothing;
      in
      {
        soa = lib.hasInfix "IN  SOA ns1.example.test." zone;
        ns = lib.hasInfix "@   IN  NS  ns1.example.test." zone;
        anyAddress = lib.hasInfix "IN  A   172.20.0.1" zone;
      };
    expected = {
      soa = true;
      ns = true;
      anyAddress = false;
    };
  };

  # Published on both protocols, because a resolver that answers only TCP
  # looks healthy and fails every ordinary lookup.
  testItIsPublishedOnBothProtocols = {
    expr = fronting.ports;
    expected = [
      "${toString port}:53/tcp"
      "${toString port}:53/udp"
    ];
  };

  # On the lab's network, which `registry-setup` depends on: it reads this
  # container's address there to write a `lab-resolv.conf` the nodes can reach.
  testItJoinsTheLabsNetwork = {
    expr = fronting.networks;
    expected = [ "example" ];
  };

  # The TSIG key is in the config, because `external-dns` updates this zone
  # over RFC2136 and needs one it was told about.
  testItAuthorisesDynamicUpdates = {
    expr =
      let
        conf = fronting.volumes."/config/knot.conf".content;
      in
      {
        key = lib.hasInfix "id: externaldns-key" conf;
        acl = lib.hasInfix "action: [update, transfer]" conf;
      };
    expected = {
      key = true;
      acl = true;
    };
  };

  # Editing the machine's resolver needs `sudo` and reaches outside the lab, so
  # a deployer opts in — and the steps that do it and undo it are simply not
  # there otherwise.
  testTheHostResolverIsOnlyTouchedWhenAsked = {
    expr = {
      off = lib.attrNames (stepsOf { });
      on = lib.attrNames (stepsOf {
        inputs.configureHost = true;
      });
    };
    expected = {
      off = [ ];
      on = [
        "dns-setup"
        "dns-teardown"
      ];
    };
  };
}
