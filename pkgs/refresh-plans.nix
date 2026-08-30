{
  lib,
  pkgs,
  cata,
}:

pkgs.writeShellApplication {
  name = "refresh-plans";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    cata

    # It shells out to `nix eval`.
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"
    outdir="''${1:-examples/labs/tests/plan-snapshots}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-plans [outdir]" >&2
      echo "" >&2
      echo "Rewrites the committed step order for every lab, both directions." >&2
      echo "Run it when a diff from plan-deploy-<lab> or plan-teardown-<lab>" >&2
      echo "is intended, and read the diff: the order is derived now, so a" >&2
      echo "step that moved says an edge changed, and an edge that changed" >&2
      echo "without anyone meaning it is the failure these pin." >&2
      exit 64
    fi

    mkdir -p "$outdir"

    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    # `labPlans`, not `labs`: a fixture lab renders and snapshots but is never
    # stood up, so the CLI cannot resolve it by name. `--from-file` takes the
    # evaluated plan directly and produces byte-identical text either way.
    plans=$(nix eval --json \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.labPlans")

    for lab in $(printf '%s' "$plans" | jq -r 'keys[]'); do
      for direction in deploy teardown; do
        case "$direction" in
          deploy) key=deploymentPlan; flag="" ;;
          teardown) key=teardownPlan; flag="--teardown" ;;
        esac

        printf '%s' "$plans" | jq ".\"$lab\".$key" > "$work/plan.json"

        # shellcheck disable=SC2086
        cata lab plan --stable $flag --from-file "$work/plan.json" \
          > "$outdir/$lab.$direction.expected.txt"
      done

      echo "  $lab" >&2
    done

    echo "refreshed $(printf '%s' "$plans" | jq -r 'keys|length') labs in $outdir" >&2
  '';
}
