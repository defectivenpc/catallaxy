# `lib.runTests` suites, run as derivations.
#
# The suites over the lab system went with the implementation they tested, with the
# hand-written `pure`/`withPkgs` tables and the `unrunTests` assertion that
# kept them honest. Both come back with the platform.
{ lib, pkgs }:

let
  testsDir = ../../lib/tests;

  mkCheck =
    name: results:
    pkgs.runCommand "${name}-tests" { } ''
      cat <<'EOF' > $out
      ${builtins.toJSON results}
      EOF
      if [ ${toString (builtins.length results)} -ne 0 ]; then
        echo "${name} FAILED:" >&2
        cat $out >&2
        exit 1
      fi
    '';

  floesDir = ../../floes/tests;

  nixFilesIn =
    dir:
    lib.attrNames (
      lib.filterAttrs (file: kind: kind == "regular" && lib.hasSuffix ".nix" file) (builtins.readDir dir)
    );

  pure = {
    floe-core = testsDir + "/floe-core.nix";
    floe-cluster = testsDir + "/floe-cluster.nix";
    secret-refs = testsDir + "/secret-refs.nix";
    secret-generate = testsDir + "/secret-generate.nix";

    # Suites for code already in the tree that was, until now, untested here:
    # they were parked alongside the lab system and test none of it.
    #
    util-network = testsDir + "/util-network.nix";
    util-duration = testsDir + "/util-duration.nix";
    util-hcl = testsDir + "/util-hcl.nix";
    util-idempotent-job = testsDir + "/util-idempotent-job.nix";
    util-wait = testsDir + "/util-wait.nix";
    manifest-graph = testsDir + "/manifest-graph.nix";
    manifest-autoedges = testsDir + "/manifest-autoedges.nix";
    plan-graph = testsDir + "/plan-graph.nix";
    render-infra = testsDir + "/render-infra.nix";
  };

  # Discovered, not listed. A hand-written list beside a `readDir` only ever
  # achieves failing when someone adds a floe and forgets to name it here.
  # `support.nix` is the harness, not a suite.
  floeSuiteFiles = lib.filter (f: f != "support.nix") (nixFilesIn floesDir);

  floeSuites = lib.listToAttrs (
    map (file: {
      name = "floe-${lib.removeSuffix ".nix" file}";
      value = import (floesDir + "/${file}") { inherit lib pkgs; };
    }) floeSuiteFiles
  );

  # Discovery cuts the other way too: a floe added to the set with no suite
  # beside it is silent, because there is no name here for its absence to
  # fail. `lab-dns` and `k3d-cluster` both sat like that. Flattened across
  # `cluster` and `provisioners`, the way `lib/lab.nix` flattens it.
  shippedFloes = lib.attrNames (lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../../floes)));

  suitedFloes = map (lib.removeSuffix ".nix") floeSuiteFiles;

  floesWithNoSuite = lib.subtractLists suitedFloes shippedFloes;
  suitesWithNoFloe = lib.subtractLists shippedFloes suitedFloes;

  suites = lib.mapAttrs (_: path: import path { inherit lib; }) pure // floeSuites;

  # A new `lib/tests/*.nix` would otherwise sit there running nowhere and
  # looking like coverage.
  registeredFiles = map baseNameOf (lib.attrValues pure);

  unrunTests = lib.subtractLists registeredFiles (nixFilesIn testsDir);
in
assert lib.assertMsg (unrunTests == [ ]) ''
  lib/tests holds test files no check runs: ${lib.concatStringsSep ", " unrunTests}.
  Add each to `pure` in nix/checks/lib-tests.nix.
'';
assert lib.assertMsg (floesWithNoSuite == [ ]) ''
  floes/default.nix ships floes with no isolation suite: ${lib.concatStringsSep ", " floesWithNoSuite}.
  Add floes/tests/<name>.nix for each. A floe checked only through a lab is
  checked only in the labs that happen to include it.
'';
assert lib.assertMsg (suitesWithNoFloe == [ ]) ''
  floes/tests holds suites for floes the set does not ship: ${lib.concatStringsSep ", " suitesWithNoFloe}.
  Either add the floe to floes/default.nix or delete the suite.
'';
lib.mapAttrs mkCheck suites
