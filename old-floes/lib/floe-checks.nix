# The quality gates a floe set is held to, as a function of the set.
#
# `mkLabChecks` gates a lab; this gates the floes a lab is built from. They
# were the same thing while the only floe set was the one in this repo: each
# gate read its floe names off `modules/lab/cluster/floes` and could not be
# pointed anywhere else, so an operator bringing their own set inherited the
# platform's graph management and none of its standards.
#
# Everything here is a rule about floes in general rather than about the ones
# catallaxy ships, which is what makes it the platform's to publish and not
# the distro's to keep.
#
#     mkFloeChecks {
#       floes = myFloeSet.cluster;
#       inherit mkLab;
#       labs = { my-lab = ...; };     # labs that enable them
#       sourceDir = ./floes;          # omit if the set has no directory
#     }
{
  lib,
  pkgs,
}:

let
  mkFloeChecks =
    {
      # The cluster-scope floe set under test: name -> module. Names come from
      # here rather than from a directory listing, so a set assembled in
      # memory is checkable and a directory that happens to contain a stray
      # folder is not.
      floes,

      # Builds the probe lab the export rule needs.
      mkLab,

      # The labs that enable these floes. Image and network coverage are
      # claims a floe can only make good on when something switches it on, so
      # with no labs those two gates have nothing to compare against.
      labs ? { },

      # Where the floes' source lives. Rule 1 is enforced by reading source
      # text, which a set of module values cannot provide. Null means the
      # boundary check is skipped rather than silently passing.
      sourceDir ? null,

      # Floes that render whatever a lab hands them, so only a lab can know.
      # An entry is a claim that the floe cannot know, not that nobody got
      # round to it.
      cannotKnowItsImages ? [ ],
      cannotKnowItsTraffic ? [ ],
    }:
    import ./floe-checks/exports.nix {
      inherit
        lib
        pkgs
        mkLab
        floes
        ;
    }
    // import ./floe-checks/images.nix {
      inherit
        lib
        pkgs
        floes
        labs
        cannotKnowItsImages
        ;
    }
    // import ./floe-checks/network.nix {
      inherit
        lib
        pkgs
        floes
        labs
        cannotKnowItsTraffic
        ;
    }
    // lib.optionalAttrs (sourceDir != null) {
      floe-boundary =
        let
          violations = import ./floe-checks/boundary.nix { inherit lib sourceDir; };
        in
        pkgs.runCommand "floe-boundary" { } ''
          ${lib.optionalString (violations != [ ]) ''
            ${lib.concatMapStringsSep "\n" (v: "echo ${lib.escapeShellArg v} >&2") violations}
            exit 1
          ''}
          touch $out
        '';
    };
in
{
  inherit mkFloeChecks;
}
