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

  pure = {
    floe-core = testsDir + "/floe-core.nix";
    floe-cluster = testsDir + "/floe-cluster.nix";
  };

  nixFilesIn =
    dir:
    lib.attrNames (
      lib.filterAttrs (file: kind: kind == "regular" && lib.hasSuffix ".nix" file) (builtins.readDir dir)
    );

  suites = lib.mapAttrs (_: path: import path { inherit lib; }) pure;

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
