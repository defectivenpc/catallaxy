# `T.helmValues`: a chart value written as a quoted boolean.
#
# Neither of the other two guards can see this one. `chart-values` renders the
# chart and finds the value has an effect, which it does — the opposite one.
# Helm's own schema validation would catch it, for the nine of twenty-one
# charts that ship a schema.
{ lib, floeCore }:

let
  floe = import ../floe-catallaxy/prelude.nix { inherit lib floeCore; };

  accepts =
    v: (builtins.tryEval (builtins.deepSeq (floe.checkValue [ ] floe.T.helmValues v) true)).success;
in
lib.runTests {
  testAnHonestBooleanIsFine = {
    expr = accepts { redis-ha.enabled = false; };
    expected = true;
  };

  # The trap: every non-empty string is truthy in a Go template, so this
  # enables what it says it disables. `argo-cd` ships no values schema, so
  # nothing downstream would have objected.
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

  # Scoped to toggle-named keys, because a string-typed boolean is ordinary
  # elsewhere: velero hands `backupStorageLocation[].config` to a CR field that
  # is `map[string]string`, so this one is correct and its suite asserts it. An
  # unscoped rule reported it on its first run.
  testAStringBooleanOutsideAToggleIsLeftAlone = {
    expr = accepts {
      configuration.backupStorageLocation = [ { config.s3ForcePathStyle = "true"; } ];
    };
    expected = true;
  };

  # Charts take string-typed ports and quantities, and cilium's schema types
  # `k8sServicePort` as `["string","integer"]` — so a numeric-string rule
  # would have been wrong about a value already in the tree.
  testANumericStringIsLeftAlone = {
    expr = accepts { k8sServicePort = "6443"; };
    expected = true;
  };

  # Nothing stops at the top level: a value is as wrong nested as it is flat.
  testItReachesNestedAttributes = {
    expr = accepts { server.standalone.enabled = "false"; };
    expected = false;
  };

  testItReachesIntoLists = {
    expr = accepts { extraArgs = [ { enabled = "true"; } ]; };
    expected = false;
  };

  # `installCRDs = "false"` is the same mistake and is not caught: precision
  # was chosen over recall, because a rule with a false positive on day one is
  # a rule people switch off.
  testANonToggleNameIsNotCovered = {
    expr = accepts { installCRDs = "false"; };
    expected = true;
  };

  # `"true"` is a perfectly good *word*. Only a whole value counts.
  testAStringThatMerelyContainsOneIsFine = {
    expr = accepts { enabled = "false alarm"; };
    expected = true;
  };
}
