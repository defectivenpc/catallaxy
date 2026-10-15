{
  lib,
  pkgs,
}:

pkgs.writeShellApplication {
  name = "refresh-generated-types";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_FLAKE:-.}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-generated-types" >&2
      echo "" >&2
      echo "Rewrites the generated Kubernetes and CRD types from the charts" >&2
      echo "and API spec they are pinned to. Run it after bumping a chart in" >&2
      echo "lib/charts.nix or the source a floe's crds.nix names, and read" >&2
      echo "the diff: these types are what every rendered resource is checked" >&2
      echo "against, so a field that changed shape is a floe that will stop" >&2
      echo "evaluating, and one that vanished is a field the cluster will" >&2
      echo "reject at apply." >&2
      echo "" >&2
      echo "The Kubernetes API lands in lib/kubernetes/generated/k8s; a" >&2
      echo "floe's CRD types land in that floe's own crds/ directory." >&2
      exit 64
    fi

    types=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.generatedTypes")

    # Removed, not merely overwritten: a group whose source is gone would
    # otherwise sit there typing kinds nothing installs, and a dropped k8s
    # version would stay selectable.
    rm -rf lib/kubernetes/generated/k8s
    mkdir -p lib/kubernetes/generated
    cp -r --no-preserve=mode "$types"/k8s lib/kubernetes/generated/

    groups=0
    for dir in "$types"/*/crds; do
      floe=$(basename "$(dirname "$dir")")
      target=$(dirname "$(find floes -name crds.nix -path "*/$floe/*" | head -1)")
      if [ -z "$target" ]; then
        echo "no floe directory for generated group set '$floe'" >&2
        exit 1
      fi
      rm -rf "$target/crds"
      cp -r --no-preserve=mode "$dir" "$target/crds"
      groups=$((groups + $(find "$dir" -name '*.nix' | wc -l)))
    done

    echo "refreshed $groups CRD groups across floes, and" \
      "$(find lib/kubernetes/generated/k8s -name '*.nix' | wc -l) API version(s)" >&2
  '';
}
