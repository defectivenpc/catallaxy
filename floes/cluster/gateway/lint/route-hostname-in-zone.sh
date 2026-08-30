set -eu

# The backstop for `kinds.mkRoute`'s in-zone check.
#
# `mkRoute` refuses an out-of-zone hostname at construction, which is where the
# error is most useful — the eval trace names the floe that asked. But a floe
# is free to hand-write an HTTPRoute, and `cluster.resources` and a raw YAML
# both bypass the constructor entirely. This reads what was actually rendered,
# so it holds regardless of how the route was built.
#
# A route naming a host outside the zone attaches happily and then serves
# nothing: the wildcard certificate does not cover it, and no DNS in the lab
# answers for it.

# -L because a wave directory is a symlink into the store, and find does not
# descend into one without it. Without this the file list is empty and the
# check passes by having nothing to look at.
files=$(find -L "$MANIFEST_DIR" -name '*.yaml' -type f)

if [ -z "$files" ]; then
  jq -n --arg d "$MANIFEST_DIR" \
    '[{severity: "error", resource: "lint", message: ("no manifests found under " + $d + ", so this check verified nothing")}]'
  exit 0
fi

# Every zone a Gateway in this cluster declares, off the label the gateway
# floe renders. A lab with two gateways on two domains is then handled without
# either knowing about the other.
#
# `|| true`, because `grep -v` exits 1 when it filters everything out — which
# is exactly the no-Gateway-label case this next block exists to report. Under
# `pipefail` and `errexit` the assignment would take the script down instead,
# and a check that dies silently reads as a check that passed.
#
# shellcheck disable=SC2086
zones=$(yq -N '
  select(.kind == "Gateway")
  | .metadata.labels["catallaxy.io/base-domain"] // ""
' $files | { grep -v '^$' || true; } | sort -u)

# A cluster with routes and no Gateway declaring a zone is not "everything is
# in zone" — it is this check having nothing to compare against, which is how
# a check passes for the wrong reason. Say so.
if [ -z "$zones" ]; then
  # No `head -1`: it closes the pipe, yq takes SIGPIPE, and under `pipefail`
  # the whole script dies with no output — which reads as a passing check.
  #
  # shellcheck disable=SC2086
  anyRoute=$(yq -N 'select(.kind == "HTTPRoute" or .kind == "TLSRoute") | .metadata.name' $files)
  if [ -n "$anyRoute" ]; then
    jq -n '[{severity: "error", resource: "lint", message: "routes exist but no Gateway declares catallaxy.io/base-domain, so no route hostname could be checked against a zone"}]'
  else
    printf '[]'
  fi
  exit 0
fi

# shellcheck disable=SC2086
routes=$(yq -N -o=tsv '
  select(.kind == "HTTPRoute" or .kind == "TLSRoute")
  | [.kind, .metadata.name, (.spec.hostnames[] // "")]
' $files)

findings='[]'
while IFS=$'\t' read -r kind name host; do
  [ -n "${host:-}" ] || continue

  matched=no
  while read -r zone; do
    [ -n "$zone" ] || continue
    if [ "$host" = "$zone" ] || [ "${host%".$zone"}" != "$host" ]; then
      matched=yes
      break
    fi
  done <<EOF
$zones
EOF

  [ "$matched" = yes ] && continue

  findings=$(printf '%s' "$findings" | jq \
    --arg r "$kind/$name" \
    --arg m "asks for hostname '$host', which is outside every zone a Gateway in this cluster serves ($(printf '%s' "$zones" | tr '\n' ' ')). The wildcard certificate does not cover it and no DNS in the lab answers for it." \
    '. + [{severity: "error", resource: $r, message: $m}]')
done <<EOF
$routes
EOF

printf '%s' "$findings"
