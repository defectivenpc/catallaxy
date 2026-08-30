# `lib.runTests` suites, run as derivations.
#
# The suites over the lab system are parked in `old-floes/lib/tests/`, with the
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
    # Two more are still parked because they test things that are:
    # `render-images` covers `applyToDir`, the image-lock rewriting that comes
    # back with `lab.images`, and `drift` covers the argocd lowering.
    util-network = testsDir + "/util-network.nix";
    util-duration = testsDir + "/util-duration.nix";
    util-wait = testsDir + "/util-wait.nix";
    manifest-graph = testsDir + "/manifest-graph.nix";
    manifest-autoedges = testsDir + "/manifest-autoedges.nix";
    plan-graph = testsDir + "/plan-graph.nix";
  };

  # Discovered, not listed. A hand-written list beside a `readDir` only ever
  # achieves failing when someone adds a floe and forgets to name it here.
  # `support.nix` is the harness, not a suite.
  floeSuites = lib.listToAttrs (
    map (file: {
      name = "floe-${lib.removeSuffix ".nix" file}";
      value = import (floesDir + "/${file}") { inherit lib pkgs; };
    }) (lib.filter (f: f != "support.nix") (nixFilesIn floesDir))
  );

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
lib.mapAttrs mkCheck suites
