{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-option-docs";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    outdir="''${1:-docs/generated}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-option-docs [outdir]" >&2
      echo "" >&2
      echo "Rewrites the generated option reference. Run it when a diff from" >&2
      echo "option-docs is intended, and read the diff: it is the option tree a" >&2
      echo "lab file writes against, so a default that moved without anyone" >&2
      echo "meaning it is somebody else's lab changing." >&2
      exit 64
    fi

    mkdir -p "$outdir"

    docs=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.optionDocs")

    # Stale pages removed, not merely overwritten: a page whose route is gone
    # would otherwise sit there describing options nothing declares.
    rm -rf "$outdir"/options "$outdir"/cli
    cp -r --no-preserve=mode "$docs"/options "$docs"/cli "$outdir/"
    cp --no-preserve=mode "$docs"/SUMMARY.md "$outdir/SUMMARY.md"

    echo "refreshed $(find "$outdir" -name '*.md' | wc -l) pages in $outdir" >&2
  '';
}
