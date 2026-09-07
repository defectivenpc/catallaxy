{
  lib,
  pkgs,
}:

# What is still running that a lab made, and deleting it.
#
# The lab tags everything it creates. That is what makes a leak findable: a
# cluster nobody can list by lab is a cluster nobody notices is still running,
# and the bill is the first thing that tells you.
#
# Deliberately *not* built on the lab document. It runs after a failed run,
# when the lab may not evaluate, may not be in the flake, and may have been
# edited since — the same reason `cata lab cleanup` reads docker labels rather
# than a rendered tree. All it needs is a tag and a token.
#
# Three object types, listed and deleted separately and in this order. A
# cluster's load balancers and volumes are made by its cloud controller and
# outlive it: delete the cluster first and they are orphaned with nothing left
# that names them.
pkgs.writeShellApplication {
  name = "cata-cloud-reap";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
  ];

  text = ''
    set -uo pipefail

    check_only=0
    if [ "''${1:-}" = "--check" ]; then
      check_only=1
      shift
    fi

    tag="''${1:-}"
    if [ -z "$tag" ]; then
      echo "usage: cata-cloud-reap [--check] <tag>" >&2
      echo "" >&2
      echo "Lists, and unless --check deletes, everything carrying <tag>." >&2
      echo "--check exits non-zero when anything is found and deletes nothing," >&2
      echo "which is what the e2e runner uses before and after a run." >&2
      exit 64
    fi

    : "''${DIGITALOCEAN_TOKEN:?set it to the token whose account should be swept}"

    api="https://api.digitalocean.com/v2"
    auth=(-H "Authorization: Bearer $DIGITALOCEAN_TOKEN" -H "Content-Type: application/json")

    found=0

    # `list` and `delete` are separate so `--check` never deletes: the
    # difference between the two modes is one branch, not two code paths that
    # could disagree about what "everything" means.
    sweep() {
      local kind="$1" path="$2" filter="$3"
      local ids
      ids=$(curl -sfS "''${auth[@]}" "$api/$path?per_page=200" | jq -r "$filter" || true)

      [ -n "$ids" ] || return 0

      while read -r id; do
        [ -n "$id" ] || continue
        found=1
        if [ "$check_only" = 1 ]; then
          echo "  $kind $id" >&2
        else
          echo "  deleting $kind $id" >&2
          curl -sfS -X DELETE "''${auth[@]}" "$api/$path/$id" >/dev/null || \
            echo "  (could not delete $kind $id)" >&2
        fi
      done <<< "$ids"
    }

    # Clusters first when deleting: DOKS releases its own load balancers on
    # cluster delete, so sweeping LBs afterwards catches only what it did not.
    sweep cluster "kubernetes/clusters" \
      ".kubernetes_clusters // [] | map(select(.tags // [] | index(\"$tag\"))) | .[].id"

    # Then what a cluster's cloud controller made and may have left. Load
    # balancers and volumes are tagged by the controller from the cluster's
    # own tags, so the same tag finds them.
    sweep load-balancer "load_balancers" \
      ".load_balancers // [] | map(select(.tags // [] | index(\"$tag\"))) | .[].id"

    sweep volume "volumes" \
      ".volumes // [] | map(select(.tags // [] | index(\"$tag\"))) | .[].id"

    if [ "$check_only" = 1 ]; then
      [ "$found" = 0 ] && exit 0
      exit 1
    fi

    if [ "$found" = 0 ]; then
      echo "nothing tagged $tag" >&2
    fi
  '';
}
