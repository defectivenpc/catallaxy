{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-allocations";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    out="''${1:-examples/labs/tests/allocations.json}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-allocations [file]" >&2
      echo "" >&2
      echo "Rewrites the committed address plan. Read the diff: a line that" >&2
      echo "moved is a lab whose port or subnet moved, for everyone." >&2
      exit 64
    fi

    dir=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.allocations")

    cp --no-preserve=mode "$dir/allocations.json" "$out"
    echo "refreshed the address plan in $out" >&2
  '';
}
