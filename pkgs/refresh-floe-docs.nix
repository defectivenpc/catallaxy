{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-floe-docs";

  runtimeInputs = [
    pkgs.coreutils

    # It shells out to `nix build`.
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    outdir="''${1:-docs/floes}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-floe-docs [outdir]" >&2
      echo "" >&2
      echo "Rewrites the committed interface of every floe. Run it when a diff" >&2
      echo "from floe-interface-<name> is intended, and read the diff: it is the" >&2
      echo "floe as everything outside it sees it, so a line that moved without" >&2
      echo "anyone meaning it is somebody else's contract changing." >&2
      exit 64
    fi

    mkdir -p "$outdir"

    # One derivation holding every floe's document, and the checks diff against
    # the same one. Copying out of it is what makes the two byte-identical by
    # construction rather than by a comment asking them to be.
    docs=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.floeInterfaces")

    # Stale files removed, not merely overwritten: a floe that was deleted
    # leaves a document describing something that no longer exists, and the
    # per-floe checks would never look at it again to say so.
    rm -f "$outdir"/*.md

    # `--no-preserve=mode`: the source is in the store and read-only, so
    # copying the mode across leaves a 0444 file the next run cannot write.
    cp --no-preserve=mode "$docs"/*.md "$outdir/"

    echo "refreshed $(find "$docs" -name '*.md' | wc -l) floe interfaces in $outdir" >&2
  '';
}
