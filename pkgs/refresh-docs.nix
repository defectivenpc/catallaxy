# Rewrite every generated page under `docs/generated/`.
#
# One app, because there is one tree. It was `refresh-floe-docs` writing
# `docs/floes/` and `refresh-option-docs` writing `docs/generated/` — two
# commands for two directories whose only real difference was which generator
# filled them, which is not a distinction a reader of the tree has.
#
# Every page is copied out of the derivation the checks diff against, so the
# committed tree and the check read one store path rather than two pipelines
# that can disagree.
{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-docs";

  runtimeInputs = [
    pkgs.coreutils

    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    outdir="''${1:-docs/generated}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-docs [outdir]" >&2
      echo "" >&2
      echo "Rewrites every generated reference page. Run it when a diff from" >&2
      echo "floe-interface-<name> or option-docs is intended, and read the diff:" >&2
      echo "" >&2
      echo "  floes/      the floe as everything outside it sees it, so a line" >&2
      echo "              that moved is somebody else's contract changing" >&2
      echo "  signatures/ what one module promises another, and which floes" >&2
      echo "              answer and ask for each" >&2
      echo "  options/    the option tree a lab file writes against, so a" >&2
      echo "              default that moved is somebody else's lab changing" >&2
      exit 64
    fi

    system="${pkgs.stdenv.hostPlatform.system}"
    out() { nix build --no-link --print-out-paths "$flake#legacyPackages.$system.$1"; }

    pages=$(out referencePages)
    options=$(out optionDocs)

    mkdir -p "$outdir"

    # Removed rather than merely overwritten. A floe that was deleted leaves a
    # page describing something that no longer exists, and the per-floe checks
    # would never look at it again to say so; a page whose route is gone would
    # sit there describing options nothing declares.
    rm -rf "$outdir"/floes "$outdir"/signatures "$outdir"/options "$outdir"/cli

    # `--no-preserve=mode`: the source is in the store and read-only, so
    # copying the mode across leaves a 0444 file the next run cannot write.
    cp -r --no-preserve=mode "$pages"/floes "$pages"/signatures "$outdir"/
    cp -r --no-preserve=mode "$options"/options "$options"/cli "$outdir"/
    cp --no-preserve=mode "$options"/SUMMARY.md "$outdir"/SUMMARY.md

    echo "refreshed $(find "$outdir" -name '*.md' | wc -l) pages in $outdir" >&2
  '';
}
