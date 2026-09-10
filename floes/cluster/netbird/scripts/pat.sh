#!/bin/sh
# Ensure netbird has a personal access token the operator can use, and that
# the account it belongs to is configured the way a lab needs.
#
# This is the one imperative step in the whole floe, and it exists because a
# netbird PAT is minted by netbird and owned by nobody. kaniop owns the
# service account and rotates its credential; netbird-operator owns groups,
# setup keys, routers and resources. The token *between* them has no owner, so
# it is the only thing here that needs healing.
#
# Run as a Job at install and as a CronJob afterwards, from this same file.
# The difference is only how often it is asked; what it does is identical, and
# what it does first is check whether there is anything to do.
#
# It is a heal against a runtime check, never a compile-time assertion: it
# asks netbird whether the current token still works, and mints only when the
# answer is no. Rotation, revocation and a restored-from-backup store all look
# the same from here, which is the point.
set -eu

log() { echo "[netbird-pat] $*" >&2; }

# The lab's CA, mounted where the wait helper puts it. netbird's API and
# kanidm's token endpoint are both served from it.
CACERT=""
if [ -f "$CA_FILE" ]; then
  CACERT="--cacert $CA_FILE"
fi

api() {
  method="$1"
  path="$2"
  shift 2
  curl -sS $CACERT -X "$method" \
    -H "Authorization: Token $PAT" \
    -H "Accept: application/json" \
    "$NB_URL/api/$path" "$@"
}

# ---- is there anything to do? ---------------------------------------------

PAT=$(kubectl -n "$NB_NS" get secret "$OUT_SECRET" \
  -o "jsonpath={.data.$OUT_KEY}" 2>/dev/null | base64 -d 2>/dev/null || true)

if [ -n "$PAT" ]; then
  code=$(curl -sS -o /dev/null -w '%{http_code}' $CACERT \
    -H "Authorization: Token $PAT" "$NB_URL/api/groups" 2>/dev/null || echo 000)
  case "$code" in
  2*)
    log "existing token still accepted; nothing to do"
    exit 0
    ;;
  401 | 403)
    log "existing token rejected with HTTP $code; re-minting"
    ;;
  *)
    # Not an authentication answer. A management that is starting, or a
    # network that is briefly gone, is not a reason to mint a second token —
    # and minting one on every blip is how an account accumulates hundreds.
    log "management answered HTTP $code, which says nothing about the token; leaving it alone"
    exit 0
    ;;
  esac
fi

# ---- become somebody ------------------------------------------------------
#
# The service account's kanidm API token is not an OIDC token and netbird will
# not accept it. Token exchange turns it into an access token issued *for the
# netbird client*, with the audience netbird checks — which is the only reason
# a machine can hold an identity here at all.

BOT=$(kubectl -n "$SA_NS" get secret "$SA_SECRET" \
  -o "jsonpath={.data.$SA_KEY}" 2>/dev/null | base64 -d 2>/dev/null || true)

if [ -z "$BOT" ]; then
  log "service account token $SA_NS/$SA_SECRET key '$SA_KEY' is missing."
  log "kaniop mints it after the KanidmServiceAccount reconciles; if it never"
  log "appears, that CR is what to look at and not this Job."
  exit 1
fi

log "exchanging the service account token for one netbird will accept"
RESP=$(curl -sS $CACERT \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  --data-urlencode "subject_token=$BOT" \
  --data-urlencode "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "scope=openid email profile groups" \
  "$TOKEN_ENDPOINT") || {
  log "kanidm refused the exchange: $RESP"
  exit 1
}

JWT=$(echo "$RESP" | jq -r '.access_token // empty')
if [ -z "$JWT" ]; then
  log "no access_token in the exchange response: $RESP"
  exit 1
fi

# ---- mint ------------------------------------------------------------------
#
# The first identity to present itself to a fresh netbird becomes the account
# owner, which is why this works with nobody at a keyboard: the service
# account is that identity.

SELF=$(curl -sS $CACERT -H "Authorization: Bearer $JWT" \
  -H "Accept: application/json" "$NB_URL/api/users/self" | jq -r '.id // empty')

if [ -z "$SELF" ]; then
  log "netbird did not recognise the exchanged token; check that the client id"
  log "'$CLIENT_ID' matches the audience management validates against."
  exit 1
fi

log "minting a token for user $SELF"
MINTED=$(curl -sS $CACERT -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  "$NB_URL/api/users/$SELF/tokens" \
  -d "{\"name\":\"$TOKEN_NAME\",\"expires_in\":$TOKEN_DAYS}")

PAT=$(echo "$MINTED" | jq -r '.plain_token // empty')
if [ -z "$PAT" ]; then
  log "no plain_token in the mint response: $MINTED"
  exit 1
fi

kubectl -n "$NB_NS" create secret generic "$OUT_SECRET" \
  --from-literal="$OUT_KEY=$PAT" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

log "token written to $NB_NS/$OUT_SECRET"

# ---- and configure the account it owns -------------------------------------
#
# Defaults netbird ships that a lab does not want: a mesh where every peer and
# every user waits for someone to approve them is a mesh nothing joins
# unattended. Applied every time the token is minted, and idempotent — the
# settings are compared before they are written.

ACCOUNT=$(api GET accounts | jq -r '.[0].id // empty')
if [ -z "$ACCOUNT" ]; then
  log "no account visible; leaving settings alone"
  exit 0
fi

CUR=$(api GET accounts | jq -r '.[0].settings')
NEW=$(echo "$CUR" | jq '
    .extra.user_approval_required = false
  | .extra.peer_approval_enabled  = false
  | .jwt_groups_enabled           = true
  | .jwt_groups_claim_name        = "groups"
')

if [ "$CUR" = "$NEW" ]; then
  log "account $ACCOUNT already configured"
else
  log "configuring account $ACCOUNT: no approval gates, groups from the token"
  api PUT "accounts/$ACCOUNT" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --argjson s "$NEW" '{settings: $s}')" >/dev/null
fi
