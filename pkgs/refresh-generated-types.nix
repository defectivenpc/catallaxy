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
    outdir="''${1:-lib/kubernetes/generated}"

    if [ "''${1:-}" = "--help" ]; then
      echo "usage: refresh-generated-types [outdir]" >&2
      echo "" >&2
      echo "Rewrites the generated Kubernetes and CRD types from the charts" >&2
      echo "and API spec they are pinned to. Run it after bumping a chart in" >&2
      echo "lib/charts.nix or a source in nix/crd-types.nix, and read the" >&2
      echo "diff: these types are what every rendered resource is checked" >&2
      echo "against, so a field that changed shape is a floe that will stop" >&2
      echo "evaluating, and one that vanished is a field the cluster will" >&2
      echo "reject at apply." >&2
      exit 64
    fi

    types=$(nix build --no-link --print-out-paths \
      "$flake#legacyPackages.${pkgs.stdenv.hostPlatform.system}.generatedTypes")

    # Removed, not merely overwritten: a group whose source is gone would
    # otherwise sit there typing kinds nothing installs, and a dropped k8s
    # version would stay selectable.
    rm -rf "$outdir"/k8s "$outdir"/crds "$outdir"/index.nix
    mkdir -p "$outdir"
    cp -r --no-preserve=mode "$types"/k8s "$types"/crds "$outdir/"
    cp --no-preserve=mode "$types"/index.nix "$outdir/index.nix"

    echo "refreshed $(find "$outdir"/crds -name '*.nix' | wc -l) CRD groups" \
      "and $(find "$outdir"/k8s -name '*.nix' | wc -l) API version(s) in $outdir" >&2
  '';
}
