{
  lib,
  pkgs,
  cataWrapped,
}:

# The runner that spends money.
#
# `pkgs/e2e.nix` proves a lab stands up on a machine with nothing but docker.
# This proves one stands up against a real account — and, more importantly,
# that nothing survives when it comes down. Those are different claims and
# this is a different runner, not a flag on the first: the free one is what CI
# runs on every change, and putting a billable lab in that matrix is a mistake
# nobody makes twice.
#
# Four things it does that the free runner does not:
#
#   - refuses to start unless the account is already clean for this lab, so a
#     leak from a previous run is found before a second one is layered on it
#   - traps on every exit path and reaps, because the failure that strands
#     resources is the one that does not reach the teardown
#   - asserts emptiness per *object type* after destroy — clusters, load
#     balancers and volumes separately, because LBs and volumes are what
#     outlive a cluster and they are what the bill is for
#   - requires `--infra`, which `cata` already gates the apply behind
pkgs.writeShellApplication {
  name = "cata-e2e-cloud";

  runtimeInputs = [
    cataWrapped
    pkgs.coreutils
    pkgs.jq
    pkgs.curl
    pkgs.nix
  ];

  text = ''
    set -uo pipefail

    flake="''${CATA_E2E_FLAKE:-.}"
    lab="''${1:-}"

    system=${pkgs.stdenv.hostPlatform.system}

    matrix=$(nix eval --json "$flake#legacyPackages.$system.cloudE2eLabs")

    if [ -z "$lab" ]; then
      echo "usage: cata-e2e-cloud <lab>" >&2
      echo "" >&2
      echo "Stands a lab up against a real cloud account and destroys it again." >&2
      echo "It creates billable resources. Nothing here runs in \`nix flake check\`." >&2
      echo "" >&2
      echo "labs this can stand up:" >&2
      printf '%s' "$matrix" | jq -r 'to_entries[] | select(.value.eligible) | "  \(.key)  [\(.value.providers|join(", "))]"' >&2
      echo "" >&2
      echo "and the ones it cannot, with the reason:" >&2
      printf '%s' "$matrix" | jq -r 'to_entries[] | select(.value.eligible|not) | "  \(.key): \(.value.reasons[0])"' >&2
      exit 64
    fi

    # Re-derived here rather than trusted from the caller, the same way the
    # free runner does it: the matrix is the lab's own answer.
    if [ "$(printf '%s' "$matrix" | jq -r --arg l "$lab" '.[$l].eligible // "missing"')" != "true" ]; then
      echo "cata-e2e-cloud: $lab is not eligible." >&2
      printf '%s' "$matrix" | jq -r --arg l "$lab" '.[$l].reasons[]? | "  " + .' >&2
      exit 64
    fi

    tag=$(printf '%s' "$matrix" | jq -r --arg l "$lab" '.[$l].tag')

    # Before anything is created. A missing token discovered halfway through
    # an apply leaves whatever the first half made and nothing that knows to
    # clean it up.
    missing=""
    while read -r var; do
      [ -n "$var" ] || continue
      if [ -z "''${!var:-}" ]; then missing="$missing $var"; fi
    done < <(printf '%s' "$matrix" | jq -r --arg l "$lab" '.[$l].requiredEnv[]?')

    if [ -n "$missing" ]; then
      echo "cata-e2e-cloud: $lab needs these set and they are not:$missing" >&2
      exit 64
    fi

    reap() {
      echo "" >&2
      echo "=== reaping anything tagged $tag ===" >&2
      ${placeholder "out"}/bin/cata-cloud-reap "$tag" || true
    }

    # Every exit path, not just the failing ones. The run that strands
    # resources is the one that does not reach its teardown, and that is
    # exactly the run whose last line nobody reads.
    trap reap EXIT

    echo "=== the account is clean for $lab before we start ===" >&2
    if ! ${placeholder "out"}/bin/cata-cloud-reap --check "$tag"; then
      echo "cata-e2e-cloud: objects tagged $tag already exist." >&2
      echo "A previous run leaked. Reap them before layering another on top:" >&2
      echo "  nix run .#cloud-reap -- $tag" >&2
      exit 1
    fi

    echo "=== lab up --infra ===" >&2
    start=$(date +%s)
    cata lab up "$lab" --infra || exit 1
    up_seconds=$(( $(date +%s) - start ))

    echo "=== lab verify ===" >&2
    cata lab verify "$lab" || exit 1

    # The same idempotence claim the free runner makes, and it matters more
    # here: a second apply that recreates a cloud cluster is one that
    # destroyed a running one first.
    echo "=== lab up --infra again, and nothing changes ===" >&2
    again=$(mktemp)
    cata lab up "$lab" --infra 2>&1 | tee "$again" || exit 1

    if grep -qE "no longer matches|will be destroyed and rebuilt" "$again"; then
      echo "cata-e2e-cloud: the second up would rebuild something." >&2
      exit 1
    fi
    if grep -q "no longer declares" "$again"; then
      echo "cata-e2e-cloud: the second up would prune something it just applied." >&2
      exit 1
    fi

    echo "=== lab destroy --infra ===" >&2
    cata lab destroy "$lab" --infra || exit 1

    echo "=== nothing of this lab survived, by object type ===" >&2
    if ! ${placeholder "out"}/bin/cata-cloud-reap --check "$tag"; then
      echo "cata-e2e-cloud: the destroy left objects tagged $tag behind." >&2
      echo "They are billing. Reap them: nix run .#cloud-reap -- $tag" >&2
      exit 1
    fi

    trap - EXIT
    echo "" >&2
    echo "$lab: up in ''${up_seconds}s, verified, idempotent, destroyed clean" >&2
  '';
}
