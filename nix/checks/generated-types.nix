# The committed Kubernetes and CRD types match what their sources produce.
#
# Same shape as `option-docs` and the floe-interface checks: the tree is
# generated, so the only way it can be wrong is by being stale. Stale here is
# worse than elsewhere, because these types are what a rendered resource is
# checked against — a chart version bumped in `lib/charts.nix` without a
# refresh leaves every floe validated against the CRD of the release before.
#
# This check is also what says the tree is generated. The emitter writes no
# banner, because the repo bans `#` comments in Nix.
{
  lib,
  pkgs,
  generatedTypes,
}:

{
  generated-types = pkgs.runCommand "generated-types-check" { } ''
    if ! diff -ru ${../../lib/kubernetes/generated} ${generatedTypes} > $TMPDIR/diff; then
      cat $TMPDIR/diff >&2
      echo "" >&2
      echo "The generated Kubernetes types are stale." >&2
      echo "" >&2
      echo "They are generated from the same pinned artifacts the floes" >&2
      echo "install — the chart CRD directories in \`lib/charts.nix\` and the" >&2
      echo "API spec in \`lib/k8s-specs.nix\` — so this diff means a source" >&2
      echo "moved and the types still describe the old one. A resource is" >&2
      echo "checked against these, so the gap is checks passing against a" >&2
      echo "CRD that is no longer what gets applied." >&2
      echo "" >&2
      echo "Refresh it and read the diff:" >&2
      echo "  nix run .#refresh-generated-types" >&2
      exit 1
    fi
    touch $out
  '';
}
