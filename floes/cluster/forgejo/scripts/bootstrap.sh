set -eu

log() { echo "[forgejo-bootstrap] $*"; }

: "${API:?API env required}"
: "${REPO:?REPO env required}"
: "${USERNAME:?USERNAME env required}"
: "${PASSWORD:?PASSWORD env required}"

# Waits on the API, not on the Deployment. The pod is Ready as soon as it
# binds, and the first authenticated call after that is a 500 while Forgejo
# finishes migrating its database.
until curl -sf -o /dev/null "$API/api/healthz"; do
  log "waiting for the API"
  sleep 5
done

# Guard on the outcome, not on the precondition. "Does the repository exist"
# is the question; "did this Job run before" is not, and answering the second
# leaves an interrupted run believing it finished.
if curl -sf -u "$USERNAME:$PASSWORD" -o /dev/null "$API/api/v1/repos/$USERNAME/$REPO"; then
  log "$USERNAME/$REPO already exists"
  exit 0
fi

# `auto_init` matters: a repository with no commits has no default branch, and
# a push to `main` against one is rejected because there is nothing for the
# branch to point at.
code=$(curl -s -u "$USERNAME:$PASSWORD" -o /tmp/out -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d "{\"name\":\"$REPO\",\"auto_init\":true,\"default_branch\":\"main\",\"private\":false}" \
  "$API/api/v1/user/repos")

case "$code" in
  201) log "created $USERNAME/$REPO" ;;
  # Another run won the race. Not an error: the outcome is what was asked for.
  409) log "$USERNAME/$REPO already exists" ;;
  *) log "creating the repository failed (HTTP $code): $(cat /tmp/out)"; exit 1 ;;
esac
