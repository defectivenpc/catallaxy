{
  lib,
  pkgs,
  e2eLabs,
}:

let
  testsDir = ../../lib/tests;
  floesDir = ../../floes/tests;

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
    coredns-internal = testsDir + "/coredns-internal.nix";
    k8s-helpers = testsDir + "/k8s-helpers.nix";
    k8s-fields = testsDir + "/k8s-fields.nix";
    k3d-volumes = testsDir + "/k3d-volumes.nix";
    idempotent-job = testsDir + "/util-idempotent-job.nix";
    wait-helpers = testsDir + "/util-wait.nix";
    duration = testsDir + "/util-duration.nix";
    ident = testsDir + "/util-ident.nix";
    network = testsDir + "/util-network.nix";
    hcl = testsDir + "/util-hcl.nix";
    image-types = testsDir + "/image-types.nix";
    netpol = testsDir + "/netpol.nix";
    sbom = testsDir + "/sbom.nix";
    drift-lowering = testsDir + "/drift.nix";
    plan-graph = testsDir + "/plan-graph.nix";
    manifest-graph = testsDir + "/manifest-graph.nix";
    manifest-autoedges = testsDir + "/manifest-autoedges.nix";
    manifest-projections = testsDir + "/manifest-projections.nix";
    secret-sharing = testsDir + "/secret-sharing.nix";
    secret-stores = testsDir + "/secret-stores.nix";
    eval-floe = testsDir + "/floe/eval-floe.nix";
    cluster-lint = testsDir + "/cluster-lint.nix";
  };

  withPkgs = {
    secret-generate = testsDir + "/secret-generate.nix";
    manifest-waves = testsDir + "/manifest-waves.nix";
    floe-options = testsDir + "/floe/floe-options.nix";
    infra-refs = testsDir + "/infra/refs.nix";
    infra-providers = testsDir + "/infra/providers.nix";
    render-images = testsDir + "/render-images.nix";
  };

  nixFilesIn =
    dir:
    lib.attrNames (
      lib.filterAttrs (file: kind: kind == "regular" && lib.hasSuffix ".nix" file) (builtins.readDir dir)
    );

  # Discovered, not listed. There used to be a hand-written list here beside
  # two assertions that between them proved it equalled this readDir — forty
  # lines whose only achievement was to fail when someone added a file and
  # forgot to name it here.
  floeTests = map (lib.removeSuffix ".nix") (nixFilesIn floesDir);

  floeSuites = lib.listToAttrs (
    map (name: {
      name = "floe-${name}";
      value = import (floesDir + "/${name}.nix") { inherit lib pkgs; };
    }) floeTests
  );

  suites =
    lib.mapAttrs (_: path: import path { inherit lib; }) pure
    // lib.mapAttrs (_: path: import path { inherit lib pkgs; }) withPkgs
    // floeSuites
    // {
      self-contained = import (testsDir + "/self-contained.nix") { inherit lib e2eLabs; };

      contracts-oidc =
        import (testsDir + "/contracts/oidc-scopes.nix") { inherit lib pkgs; }
        ++ import (testsDir + "/contracts/oidc-client-type.nix") { inherit lib pkgs; };
    };
  # The floe suites are discovered, but `pure` and `withPkgs` are still
  # written out, so a new lib/tests/*.nix would otherwise sit there running
  # nowhere and looking like coverage.
  registeredFiles = map baseNameOf (lib.attrValues pure ++ lib.attrValues withPkgs) ++ [
    "self-contained.nix"
  ];

  unrunTests = lib.subtractLists registeredFiles (nixFilesIn testsDir);
in
assert lib.assertMsg (unrunTests == [ ]) ''
  lib/tests holds test files no check runs: ${lib.concatStringsSep ", " unrunTests}.
  Add each to `pure` or `withPkgs` in nix/checks/lib-tests.nix.
'';
lib.mapAttrs mkCheck suites
