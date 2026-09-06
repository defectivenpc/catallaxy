# Checks over the RFC-0001 floe implementation.
#
# The lab system's checks are parked in `old-floes/nix/checks/` along with the
# floe implementation they test; they come back as the platform is rebuilt on
# `lib/floe-core`.
{
  lib,
  pkgs,
  self,
  packages,
  treefmtEval,
  labDefs,
  mkLab,
  e2eLabs,
}:

{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  formatting = treefmtEval.config.build.check self;
}
// import ./lib-tests.nix { inherit lib pkgs; }
// import ./lab-manifests.nix { inherit lib pkgs labDefs; }
// import ./self-contained.nix { inherit lib pkgs e2eLabs; }
// import ./step-kinds.nix { inherit lib pkgs; }
// import ./ops-tool.nix { inherit lib pkgs; }
// import ./lab-checks.nix {
  inherit
    lib
    pkgs
    packages
    labDefs
    ;
  snapshotDir = ../../examples/labs/tests/plan-snapshots;
  digestDir = ../../examples/labs/tests/manifest-digests;
}
// import ./floe-gates.nix {
  inherit lib pkgs labDefs;
  floeSet = (import ../../floes).cluster;
  cannotKnowItsImages = [
    # Handed arbitrary resources and an optional chart by whoever
    # instantiates it. Enumerating what those pull is not something it can do.
    "custom"
  ];
}
// import ./lab-scope.nix {
  inherit
    lib
    pkgs
    mkLab
    ;
}
// import ./secret-sharing.nix {
  inherit
    lib
    pkgs
    labDefs
    mkLab
    ;
}
