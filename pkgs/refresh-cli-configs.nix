{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-cli-configs";

  runtimeInputs = [
    pkgs.coreutils

    # It shells out to `nix build`.
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    outdir="''${1:-examples/labs/tests/cli-configs}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-cli-configs [outdir]" >&2
      echo "" >&2
      echo "Rewrites the committed record of the document cata parses for" >&2
      echo "every lab. Run it when a diff from cliConfig-<lab> is intended," >&2
      echo "and read the diff: this is the only fixture covering how a" >&2
      echo "cluster is provisioned, so a change here that nobody meant is" >&2
      echo "one the manifest digest and the plan snapshots cannot see." >&2
      exit 64
    fi

    mkdir -p "$outdir"

    # One derivation holding every lab's file, and the check diffs against
    # the same one. Copying out of it is what makes the two byte-identical
    # by construction rather than by a comment asking them to be.
    configs=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.labCliConfigs")

    # `--no-preserve=mode`: the source is in the store and read-only, so
    # copying the mode across leaves a 0444 file the next run cannot write.
    cp --no-preserve=mode "$configs"/*.json "$outdir/"

    for f in "$configs"/*.json; do
      echo "  $(basename "$f" .json)" >&2
    done

    echo "refreshed $(find "$configs" -name '*.json' | wc -l) cli configs in $outdir" >&2
  '';
}
