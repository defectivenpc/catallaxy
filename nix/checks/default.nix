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
}:

{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  formatting = treefmtEval.config.build.check self;
}
// import ./lib-tests.nix { inherit lib pkgs; }
// import ./lab-manifests.nix { inherit lib pkgs labDefs; }
