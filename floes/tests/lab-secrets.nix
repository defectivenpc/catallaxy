# lab-secrets, alone.
#
# A collector, so the interesting thing is what the fan-in produces rather
# than what it carries. Two cases do the work: a store nobody has put a secret
# in has nothing to check, and a runtime store is not something you authored.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  secretsWith =
    without:
    (support.evalFloe {
      name = "lab-secrets";
      inherit without;
    }).link;

  stepsOf = without: (secretsWith without).provides.lab-secrets.step.steps;
  storesOf = link: link.out."catallaxy.labStores".lab-secrets;
  secretsOf = link: link.out."catallaxy.labSecrets".lab-secrets;
in
lib.runTests {

  # `direction` is `writable` worded for the CLI, derived here so that a store
  # cannot state the two differently. It was a field the store floe emitted
  # beside `writable` on its provide — one fact in two places, which the fold
  # moving into a floe is what removed.
  testItWordsWritabilityForTheCli = {
    expr = lib.mapAttrs (_: s: s.direction) (storesOf (secretsWith [ ]));
    expected.stub-labStore = "authored";
  };

  # And the record otherwise arrives verbatim, minus the two fields that exist
  # for a peer rather than for `cata`: the store's own name is the key, and
  # `writable` is what `direction` was derived from.
  testItDropsWhatOnlyAPeerReads = {
    expr = lib.attrNames (storesOf (secretsWith [ ])).stub-labStore;
    expected = [
      "backend"
      "direction"
      "removerCommand"
      "vault"
      "writerCommand"
    ];
  };

  # Same for a secret: `readableKeys` is what a projection checks against and
  # the name is the key, so neither reaches the document.
  testASecretKeepsOnlyWhatTheCliReads = {
    expr = lib.attrNames (secretsOf (secretsWith [ ])).stub-labSecret;
    expected = [
      "hostPaths"
      "keys"
      "kind"
      "store"
    ];
  };

  # The authored stores, named for the CLI to open. `writable` is the runtime
  # case — a vault, or something external a cluster pushes into at deploy —
  # and reading one of those is not what can fail silently. An authored store
  # is one you wrote by hand, where a missing environment variable or an
  # undecryptable file is found at `cata lab up` or not at all.
  testItChecksEveryAuthoredStore = {
    expr = (stepsOf [ ]).ensure-secrets.params.stores;
    expected = [ "stub-labStore" ];
  };

  # Before the services and before every cluster is created, which is as
  # early as a step can be — a lab missing a secret should fail in seconds
  # rather than after a cluster exists.
  #
  # `wants` on the services rather than `needs`: most labs run none, and a
  # lone unsatisfied anchor leaves the step unconstrained. The sort once put
  # it after both clusters were created and their manifests deployed, which is
  # the failure it exists to prevent.
  testItRunsBeforeAnythingCouldWantAValue = {
    expr = {
      before = (stepsOf [ ]).ensure-secrets.before;
      beforeClusters = (stepsOf [ ]).ensure-secrets.beforeClusters;
    };
    expected = {
      before = [ "optional:provides:lab/services" ];
      beforeClusters = "created";
    };
  };

  # A lab with stores and no secrets has nothing to check: the step exists for
  # the values, and a store nobody has put anything in is a backend nobody has
  # asked anything of yet. So there is no step at all rather than one checking
  # an empty list.
  testWithNoSecretsThereIsNothingToCheck = {
    expr = lib.attrNames (stepsOf [ "labSecret" ]);
    expected = [ ];
  };

  # And with secrets but no store the list is empty rather than absent, which
  # is the shape that says "something is held here and nothing says where" —
  # a state `floes/lab/secret.nix` refuses, so this is the belt to its braces.
  testWithNoStoreThereIsNothingToOpen = {
    expr = (stepsOf [ "labStore" ]).ensure-secrets.params.stores;
    expected = [ ];
  };

  # One fan-in, so one of these: two would emit two steps checking
  # overlapping sets of the same stores.
  testThereIsOnlyOneFanIn = {
    expr = (support.evalFloe { name = "lab-secrets"; }).def.singleton;
    expected = true;
  };
}
