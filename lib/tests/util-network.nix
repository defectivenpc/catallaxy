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
