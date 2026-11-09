# `lib.runTests` suites, run as derivations.
#
# The suites over the lab system went with the implementation they tested, with the
# hand-written `pure`/`withPkgs` tables and the `unrunTests` assertion that
# kept them honest. Both come back with the platform.
{
  lib,
  pkgs,
  floeCore,
}:

let
  testsDir = ../../../lib/tests;

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

  nixFilesIn =
    dir:
    lib.attrNames (
      lib.filterAttrs (file: kind: kind == "regular" && lib.hasSuffix ".nix" file) (builtins.readDir dir)
    );

  pure = {
    floe-cluster = testsDir + "/floe-cluster.nix";
    secret-refs = testsDir + "/secret-refs.nix";
    secret-generate = testsDir + "/secret-generate.nix";
    helm-values = testsDir + "/helm-values.nix";

    authoring-ipv4 = testsDir + "/authoring-ipv4.nix";
    k8s-duration = testsDir + "/k8s-duration.nix";
    render-hcl = testsDir + "/render-hcl.nix";
    k8s-idempotent-job = testsDir + "/k8s-idempotent-job.nix";
    k8s-wait = testsDir + "/k8s-wait.nix";
    manifest-graph = testsDir + "/manifest-graph.nix";
    manifest-autoedges = testsDir + "/manifest-autoedges.nix";
    plan-graph = testsDir + "/plan-graph.nix";
    render-infra = testsDir + "/render-infra.nix";
  };

  # `callPackageWith` hands a suite only the arguments it declares, so the ones
  # that never touch the floe library keep their `{ lib }` head and the two that
  # do just ask for `floeCore`.
  suites = lib.mapAttrs (
    _: path:
    lib.callPackageWith {
      inherit lib floeCore;

      # The two suites that build a Kubernetes API record need the spec it is
      # converted from. In scope for all of them rather than threaded to
      # those two, because `callPackageWith` gives a suite only what it asks
      # for by name.
      specFile = (import ../../../lib/kubernetes/specs.nix { inherit lib pkgs; }).specs."1.31";
    } path { }
  ) pure;

  # A new `lib/tests/*.nix` would otherwise sit there running nowhere and
  # looking like coverage.
  registeredFiles = map baseNameOf (lib.attrValues pure);

  unrunTests = lib.subtractLists registeredFiles (nixFilesIn testsDir);
in
assert lib.assertMsg (unrunTests == [ ]) ''
  lib/tests holds test files no check runs: ${lib.concatStringsSep ", " unrunTests}.
  Add each to `pure` in nix/checks/lib/lib-tests.nix.
'';
lib.mapAttrs mkCheck suites
