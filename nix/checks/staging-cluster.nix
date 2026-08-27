# The staged cluster reaches the ground: a link result, joined and elaborated,
# renders as wave directories of real Kubernetes YAML.
#
# `checks.floe-cluster` pins the merge and the derived order as values. This
# pins that the same thing survives being built — a wave with no directory, or
# a bundle whose chart templated to nothing, is invisible to a `runTests`
# assertion over the metadata.
{
  lib,
  pkgs,
  staging,
}:

{
  staging-cluster = pkgs.runCommand "staging-cluster-renders" { } ''
    set -euo pipefail
    tree=${staging.manifests}

    fail() { echo "staging cluster: $1" >&2; exit 1; }

    # Wave numbering is an artifact of the sort, not a concept, so this
    # asserts the order the sort produced rather than any wave index having
    # a meaning. Every one of these edges but `gateway.needs` was derived.
    expected="00-wave/gateway-api__crds
    00-wave/namespaces
    01-wave/gateway__controller
    02-wave/gateway__gateway
    03-wave/podinfo__podinfo"

    actual=$(cd "$tree" && find . -mindepth 2 -maxdepth 2 -type d | sed 's#^\./##' | sort)
    if [ "$actual" != "$(echo "$expected" | sed 's/^ *//')" ]; then
      echo "expected:" >&2; echo "$expected" | sed 's/^ *//' >&2
      echo "actual:" >&2;   echo "$actual" >&2
      fail "wave layout changed"
    fi

    # The chart templated rather than producing an empty file.
    grep -q 'kind: Deployment' "$tree/01-wave/gateway__controller/traefik.yaml" \
      || fail "traefik chart rendered no Deployment"

    # The route's attachment came through the sealed API_GATEWAY value, so
    # podinfo never spelled any of these three.
    route="$tree/03-wave/podinfo__podinfo/resources.yaml"
    grep -q 'name: default-gateway' "$route" || fail "route names no parent gateway"
    grep -q 'sectionName: http'     "$route" || fail "route names no listener"
    grep -q 'podinfo.minimal.test'  "$route" || fail "route carries no hostname"

    # Ownership labels are stamped, and a label value may not contain a slash.
    if grep -rq 'catallaxy.io/bundle: .*/' "$tree"; then
      fail "an ownership label carries a slash; the API server would reject the object"
    fi

    touch $out
  '';
}
