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
    tree=${labDefs."minimal.local".config.lab.out.package}/manifests/app

    fail() { echo "lab manifests: $1" >&2; exit 1; }

    [ -f "$tree/.wave-meta" ] || fail ".wave-meta is missing; the applier hard-errors on this"

    # Wave numbering is an artifact of the sort, not a concept, so this
    # asserts the order the sort produced rather than any index meaning
    # something. Every one of these edges but `gateway.needs` was derived.
    expected="00-wave/gateway-api__crds
    00-wave/namespaces
    01-wave/cert-manager__cert-manager
    02-wave/cert-manager__issuers
    03-wave/gateway__controller
    04-wave/gateway__gateway
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
    jq -e '[.waves[].bundles[].readyProbe | select(. != null) | .kind]
           | length == 5
           and all(. as $k | ["condition","jsonpath","exists","pod","kubectl-wait","script"]
                             | index($k) != null)' \
      "$tree/.wave-meta" >/dev/null || fail "a readyProbe kind the applier would reject"

    grep -q 'kind: Deployment' "$tree/03-wave/gateway__controller/traefik.yaml" \
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
