{ lib, floeCore }:

let
  floe = import ../floe-catallaxy/authoring/prelude.nix { inherit lib floeCore; };

  accepts =
    v: (builtins.tryEval (builtins.deepSeq (floe.checkValue [ ] floe.T.helmValues v) true)).success;
in
lib.runTests {
  testAnHonestBooleanIsFine = {
    expr = accepts { redis-ha.enabled = false; };
    expected = true;
  };

  testAQuotedFalseIsRefused = {
    expr = accepts { redis-ha.enabled = "false"; };
    expected = false;
  };

  testAQuotedTrueIsRefusedToo = {
    expr = accepts { hubble.enabled = "true"; };
    expected = false;
  };

  testYesAndOffAreRefusedOnAToggle = {
    expr = [
      (accepts { a.enabled = "yes"; })
      (accepts { b.enabled = "off"; })
    ];
    expected = [
      false
      false
    ];
  };

  testAStringBooleanOutsideAToggleIsLeftAlone = {
    expr = accepts {
      configuration.backupStorageLocation = [ { config.s3ForcePathStyle = "true"; } ];
    };
    expected = true;
  };

  testANumericStringIsLeftAlone = {
    expr = accepts { k8sServicePort = "6443"; };
    expected = true;
  };

  testItReachesNestedAttributes = {
    expr = accepts { server.standalone.enabled = "false"; };
    expected = false;
  };

  testItReachesIntoLists = {
    expr = accepts { extraArgs = [ { enabled = "true"; } ]; };
    expected = false;
  };

  testANonToggleNameIsNotCovered = {
    expr = accepts { installCRDs = "false"; };
    expected = true;
  };

  testAStringThatMerelyContainsOneIsFine = {
    expr = accepts { enabled = "false alarm"; };
    expected = true;
  };
}
