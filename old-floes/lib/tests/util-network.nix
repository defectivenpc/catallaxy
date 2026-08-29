{ lib }:

let
  net = import ../util/network.nix { inherit lib; };

  throws =
    expr:
    let
      r = builtins.tryEval (builtins.deepSeq expr expr);
    in
    !r.success;
in
lib.runTests {

  # The docker bridge gateway and a cluster's first assignable host are both
  # this. Three places derived it by hand while this had no callers at all.
  testFirstIPIsTheAddressAfterTheNetworks = {
    expr = net.cidrFirstIP "172.20.0.0/16";
    expected = "172.20.0.1";
  };

  testFirstIPIgnoresThePrefixLength = {
    expr = [
      (net.cidrFirstIP "10.0.0.0/8")
      (net.cidrFirstIP "10.0.0.0/24")
    ];
    expected = [
      "10.0.0.1"
      "10.0.0.1"
    ];
  };

  testFirstIPCarriesIntoTheLastOctet = {
    expr = net.cidrFirstIP "192.168.1.254/24";
    expected = "192.168.1.255";
  };

  # Only one of the three hand-rolled copies checked this. The other two
  # produced a nonsense address or failed inside `toInt`, so the check now
  # lives with the function.
  testAnIncompleteAddressIsRefused = {
    expr = throws (net.cidrFirstIP "10.0.0/8");
    expected = true;
  };

  testSomethingThatIsNotAnAddressIsRefused = {
    expr = throws (net.cidrFirstIP "not-a-cidr/8");
    expected = true;
  };

  testAnAddressInsideItsRange = {
    expr = net.ipInCidr "10.42.0.7" "10.42.0.0/16";
    expected = true;
  };

  testAnAddressOutsideItsRange = {
    expr = net.ipInCidr "10.43.0.7" "10.42.0.0/16";
    expected = false;
  };

  # The reason this exists: a lab whose pod and service subnets overlap comes
  # up and then routes to the wrong place.
  testOverlappingRangesAreDetected = {
    expr = net.cidrsOverlap "10.42.0.0/16" "10.42.128.0/17";
    expected = true;
  };

  testOverlapIsSymmetric = {
    expr = net.cidrsOverlap "10.42.128.0/17" "10.42.0.0/16";
    expected = true;
  };

  testDisjointRangesDoNotOverlap = {
    expr = net.cidrsOverlap "10.42.0.0/16" "10.43.0.0/16";
    expected = false;
  };

  testAdjacentRangesDoNotOverlap = {
    expr = net.cidrsOverlap "10.0.0.0/24" "10.0.1.0/24";
    expected = false;
  };
}
