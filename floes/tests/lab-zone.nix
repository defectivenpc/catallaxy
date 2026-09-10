# lab-zone, alone.
#
# The first floe that lives at lab scope. It installs nothing, requires
# nothing, and answers one signature — which is the whole shape worth pinning:
# a floe that exists to carry a fact the lab decides to the floes that need it.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  r = support.evalFloe {
    name = "lab-zone";
    inputs = {
      zone = "example.test";
      server = "172.20.0.1";
      port = 5399;
    };
  };
in
lib.runTests {

  # Straight through: the lab decides these and this carries them. The value
  # of the floe is not the computation, it is that two floes in two clusters
  # now read one answer instead of being handed three arguments each.
  testItAnswersWithWhatTheLabDecided = {
    expr = r.provides.zone;
    expected = {
      zone = "example.test";
      server = "172.20.0.1";
      port = 5399;
    };
  };

  # No cluster required and no component emitted. A floe at lab scope has
  # nowhere to render into, and asking it to name a cluster would be asking
  # for a dependency to satisfy a check rather than because it is true.
  testItInstallsNothingAndNeedsNoCluster = {
    expr = {
      wiring = lib.attrNames r.link.wiring.one.lab-zone;
      fromScope = lib.attrNames r.link.wiring.scope.lab-zone;
      renders = r.link.out ? "catallaxy.component";
    };
    expected = {
      wiring = [ ];
      fromScope = [ ];
      renders = false;
    };
  };

  # Every field portable, which is what lets it cross to every cluster: the
  # server is the docker bridge gateway, reachable from all of them, and the
  # zone and port are decisions rather than addresses.
  testEveryFieldTravels = {
    expr = lib.any (t: support.catallaxy.floe.T.isLocal t) (
      lib.attrValues support.catallaxy.sigs.DNS_ZONE.fields
    );
    expected = false;
  };
}
