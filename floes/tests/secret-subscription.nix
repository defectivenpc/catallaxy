# secret-subscription, alone.
#
# The half that shows what the link buys: the key it reads comes off
# `requires.publication`, so the producer's choice reaches it without either
# side deriving an address. It used to name the producing cluster and let the
# module derive the same string twice.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe {
    name = "secret-subscription";
    inputs = {
      namespace = "default";
      secret = "core-lab-ca";
      labels."catallaxy.io/trust" = "lab-ca";
    };
  };

  pull = r.bundles.subscription.resources.pull;
in
lib.runTests {

  # The producer's key, read rather than recomputed.
  testItReadsThePublishedKey = {
    expr = (lib.head pull.spec.dataFrom).extract.key;
    expected = support.stubs.publication.value.key;
  };

  # Its own store object, in its own cluster. The two store objects are two
  # objects; what has to match is the backend behind them.
  testItReadsThroughItsOwnStore = {
    expr = pull.spec.secretStoreRef;
    expected = {
      name = support.stubs.secretStore.value.storeName;
      kind = support.stubs.secretStore.value.storeKind;
    };
  };

  # Landed under the name this cluster calls it.
  testTheSecretIsNamedLocally = {
    expr = pull.spec.target.name;
    expected = "core-lab-ca";
  };

  # A label is how what reads a Secret usually finds it, so it goes through
  # the template rather than being lost.
  testLabelsReachTheSecret = {
    expr = pull.spec.target.template.metadata.labels;
    expected = {
      "catallaxy.io/trust" = "lab-ca";
    };
  };

  # A refresh, not a re-mint: the producer owns the value.
  testItRefreshesRatherThanReminting = {
    expr = pull.spec.refreshInterval;
    expected = "1h";
  };
}
