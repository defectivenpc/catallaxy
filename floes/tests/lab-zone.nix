# lab-zone, alone.
#
# The first floe that lives at lab scope. It installs nothing, requires
# nothing, and answers one signature — which is the whole shape worth pinning:
# a floe that exists to carry a fact the lab decides to the floes that need it.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  r = support.evalFloe {
    name = "lab-zone";
    inputs.zone = "example.test";
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

      port = (support.catallaxy.allocationFor "example").dns;

      server = "172.20.0.1";
    };
  };

  # No cluster required and no component emitted. A floe at lab scope has
  # nowhere to render into, and asking it to name a cluster would be asking
  # for a dependency to satisfy a check rather than because it is true.
  #
  # The network is the one thing it does resolve, and it is true: the address
  # the zone's records answer at is a fact about the network, not about the
  # zone.
  testItInstallsNothingAndNeedsNoCluster = {
    expr = {
      wiring = lib.attrNames r.link.wiring.one.lab-zone;
      renders = r.link.out ? "catallaxy.component";
    };
    expected = {
      wiring = [ "network" ];
      renders = false;
    };
  };
}
