# The lab package reaches the ground: wave directories of real YAML, and the
# index the applier walks.
#
# `checks.floe-cluster` pins the merge and the derived order as values. This
# pins that the same thing survives being built — a wave with no directory, a
# chart that templated to nothing, or a `.wave-meta` whose `dir` does not
# match what was laid down is invisible to an assertion over the metadata.
{
  lib,
  pkgs,
  labDefs,
}:

{
  lab-manifests = pkgs.runCommand "lab-manifests" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -euo pipefail
    tree=${labDefs."minimal.local".package}/manifests/app

    fail() { echo "lab manifests: $1" >&2; exit 1; }

    [ -f "$tree/.wave-meta" ] || fail ".wave-meta is missing; the applier hard-errors on this"

    # Wave numbering is an artifact of the sort, not a concept, so this
    # asserts the order the sort produced rather than any index meaning
    # something. Every one of these edges but `gateway.needs` was derived.
    #
    # `podinfo` sits last, behind the gateway it attaches a route to, and the
    # `platform__` prefixes are the platform inclusion this cluster composes.
    # The two facts are connected: a consumer beside an inclusion resolves
    # against the inclusion, which holds no bundles of its own, so this edge
    # used to have no target and disappear — podinfo landed in wave 1, three
    # waves before its Gateway. Floe's ADR 0013 is what put it back.
    expected="00-wave/namespaces
    00-wave/platform__coredns-zone__coredns
    00-wave/platform__external-secrets__crds
    00-wave/platform__gateway-api__crds
    01-wave/platform__cert-manager__cert-manager
    01-wave/platform__external-secrets__external-secrets
    02-wave/platform__cert-manager__issuers
    03-wave/platform__gateway__controller
    03-wave/platform__trust-manager__trust-manager
    04-wave/platform__gateway__gateway
    04-wave/platform__trust-manager__bundles
    05-wave/podinfo__podinfo"

    actual=$(cd "$tree" && find . -mindepth 2 -maxdepth 2 -type d | sed 's#^\./##' | sort)
    if [ "$actual" != "$(echo "$expected" | sed 's/^ *//')" ]; then
      echo "expected:" >&2; echo "$expected" | sed 's/^ *//' >&2
      echo "actual:" >&2;   echo "$actual" >&2
      fail "wave layout changed"
    fi

    # Every `dir` in the index has to be a directory that exists, or the
    # applier walks into nothing and reports success.
    jq -r '.waves[].bundles[] | select(.hasContent) | .dir' "$tree/.wave-meta" |
      while read -r d; do
        [ -d "$tree/$d" ] || fail ".wave-meta names '$d', which was never rendered"
      done

    # Probes reach the applier in the shape its enum accepts.
    #
    # `length > 0` rather than a count: how many probes a cluster has is its
    # contents, and pinning it made this check fail whenever the lab gained a
    # floe — which is a snapshot of an inventory wearing the clothes of a
    # structural assertion. What matters is that every probe that exists is a
    # kind the applier can act on, and that at least one does, so the `all`
    # below is not vacuous.
    jq -e '[.waves[].bundles[].readyProbe | select(. != null) | .kind]
           | length > 0
           and all(. as $k | ["condition","jsonpath","exists","pod","kubectl-wait","script"]
                             | index($k) != null)' \
      "$tree/.wave-meta" >/dev/null || fail "a readyProbe kind the applier would reject"

    grep -q 'kind: Deployment' "$tree/03-wave/platform__gateway__controller/traefik.yaml" \
      || fail "traefik chart rendered no Deployment"

    # The route's attachment came through the sealed API_GATEWAY value, so
    # podinfo never spelled any of these three.
    route="$tree/05-wave/podinfo__podinfo/resources.yaml"
    grep -q 'name: default-gateway' "$route" || fail "route names no parent gateway"
    grep -q 'sectionName: http'     "$route" || fail "route names no listener"
    grep -q 'podinfo.minimal.test'  "$route" || fail "route carries no hostname"

    # A label value may not contain a slash; the API server rejects the whole
    # object, not just the label.
    if grep -rq 'catallaxy.io/bundle: .*/' "$tree"; then
      fail "an ownership label carries a slash"
    fi

    touch $out
  '';
}
