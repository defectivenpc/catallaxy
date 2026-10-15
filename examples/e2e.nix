/*
  The labs a machine with docker can stand up, and the two runners that do it.

  `nix run ./examples#e2e` takes one lab name, or no argument to list them.
  `nix run ./examples#e2e-all` runs every one, `--jobs N` at a time.

  The list is here rather than in `flake.nix` because it is the only thing
  outside these two scripts that knows which labs are eligible, and it is
  baked into them: a runner that had to read its own flake back to find out
  what it can run could not be run against another checkout.

  Eligibility is not derived. A lab is eligible when somebody has watched it
  come up and go away again on a laptop; that cannot be computed from the
  declaration, so it is written down.
*/
{
  lib,
  pkgs,
  cataWrapped,
}:

let
  labs = [
    "crossplane.nop"
    "gitops.local"
    "homelab.dns"
    "homelab.local"
    "minimal.cilium"
    "minimal.local"
    "minimal.secrets"
    "minimal.talos"
    "minimal.tls"
  ];

  labList = lib.concatStringsSep "\n" labs;

  # One lab, stood up from nothing and torn back down to nothing.
  #
  # The assertion that matters is not that a lab comes up — it is that running
  # `lab up` a second time against an unchanged declaration does nothing at
  # all, and that teardown leaves nothing behind. Both are invisible to any
  # check over rendered output, and both have been wrong here before.
  one = pkgs.writeShellApplication {
    name = "cata-e2e";

    runtimeInputs = [
      cataWrapped
      pkgs.jq
      pkgs.docker-client
      pkgs.gnugrep

      pkgs.nix
    ];

    text = ''
      set -euo pipefail

      lab="''${1:-}"
      flake="''${CATA_E2E_FLAKE:-.}"

      labs="${labList}"

      if [ -z "$lab" ]; then
        echo "usage: cata-e2e <lab>" >&2
        echo "" >&2
        echo "labs this can stand up:" >&2
        printf '%s\n' "$labs" | sed 's/^/  /' >&2
        exit 64
      fi

      if ! printf '%s\n' "$labs" | grep -qxF "$lab"; then
        echo "cata-e2e: '$lab' is not in the e2e list." >&2
        echo "  The list is \`labs\` in examples/e2e.nix. Add it there if it belongs." >&2
        exit 1
      fi

      # Everything this lab owns, and nothing another one does. Host services
      # are `catallaxy-<lab>-<svc>`; k3d nodes are `k3d-<prefix>-...`, where
      # the prefix is the lab name with separators flattened.
      #
      # This used to be every container matching `^catallaxy-`, which is how
      # the script came to refuse to run at all beside another lab: it could
      # not tell whose leftovers it was looking at.
      prefix=$(printf '%s' "$lab" | tr './_ ' '----')
      ours="^(catallaxy-$lab|k3d-$prefix|$prefix)-"

      our_containers() {
        docker ps -a --format '{{.Names}} {{.ID}} {{.CreatedAt}}' \
          | grep -E "$ours" | sort || true
      }

      if [ -n "$(our_containers)" ]; then
        echo "cata-e2e: '$lab' already has containers on this machine." >&2
        echo "  This asserts that nothing survives its own teardown, so it has to" >&2
        echo "  start from nothing. Other labs may be up; only this one is in the" >&2
        echo "  way." >&2
        echo "" >&2
        our_containers >&2
        echo "" >&2
        echo "  Remove them with:" >&2
        echo "    cata lab cleanup $lab --yes" >&2
        exit 1
      fi

      workdir=$(mktemp -d)
      trap 'rm -rf "$workdir"' EXIT

      step() { echo "" >&2; echo "=== $* ===" >&2; }

      env_file=$(nix eval --raw "$flake#labs.\"$lab\".secrets.envFile" 2> /dev/null || true)
      if [ -n "$env_file" ]; then
        env_path="$flake/$env_file"
        if [ ! -f "$env_path" ]; then
          echo "cata-e2e: $lab sets lab.secrets.envFile to $env_file, and $flake does not have that file." >&2
          echo "  The path is relative to the flake root. If you just wrote the file, git add it." >&2
          exit 1
        fi
        step "loading secrets from $env_file"
        set -a
        # shellcheck disable=SC1090
        . "$env_path"
        set +a
      fi

      started=$SECONDS
      step "lab up"
      cata --flake "$flake#$lab" lab up --infra
      up_seconds=$((SECONDS - started))

      step "lab verify"
      cata --flake "$flake#$lab" lab verify

      step "lab up again, which must change nothing"
      our_containers > "$workdir/containers.before"
      cata --flake "$flake#$lab" lab up --infra 2>&1 | tee "$workdir/second-up.log"
      our_containers > "$workdir/containers.after"

      if ! diff -u "$workdir/containers.before" "$workdir/containers.after"; then
        echo "" >&2
        echo "the second 'lab up' created, destroyed or replaced a container." >&2
        echo "  Running it against a lab that already matches the declaration" >&2
        echo "  must be a no-op. A container whose ID or creation time moved was" >&2
        echo "  rebuilt, which means something read as drifted when it was not." >&2
        exit 1
      fi

      if grep -qE 'no longer matches|will be destroyed and rebuilt' "$workdir/second-up.log"; then
        echo "" >&2
        echo "the second 'lab up' reported drift against an unchanged declaration:" >&2
        grep -E 'no longer matches|will be destroyed and rebuilt' "$workdir/second-up.log" >&2
        echo "" >&2
        echo "  Either the shape record does not round-trip what was built, or a" >&2
        echo "  field is being compared that the cluster never had." >&2
        exit 1
      fi

      if grep -qE 'no longer declares' "$workdir/second-up.log"; then
        echo "" >&2
        echo "the second 'lab up' pruned resources from an unchanged declaration:" >&2
        grep -E 'no longer declares' "$workdir/second-up.log" >&2
        echo "" >&2
        echo "  Pruning compares what the cluster is labelled with against what" >&2
        echo "  the declaration names. Deleting anything here means the two" >&2
        echo "  disagree about a resource nobody changed, and the next lab to" >&2
        echo "  run loses it. A synthetic bundle missing from .declared-bundles" >&2
        echo "  did exactly this to the lab's own namespaces." >&2
        exit 1
      fi

      step "lab destroy"
      cata --flake "$flake#$lab" lab destroy --infra

      step "nothing of this lab survived the teardown"
      if [ -n "$(our_containers)" ]; then
        echo "teardown left containers behind:" >&2
        our_containers >&2
        exit 1
      fi

      cata --flake "$flake#$lab" lab status --json > "$workdir/after.json"
      jq -e '[.services[] | select(.running)] == [] and [.clusters[] | select(.reachable)] == []' \
        "$workdir/after.json" > /dev/null \
        || { echo "teardown left services or clusters running:" >&2; jq . "$workdir/after.json" >&2; exit 1; }

      if docker network ls --format '{{.Name}}' | grep -qx "$lab"; then
        echo "docker network '$lab' survived the teardown" >&2
        exit 1
      fi

      # A stack's state is the only record of what it made. Teardown claiming
      # the lab is gone while state still lists resources would be a claim
      # about a cloud account nobody checked. Nothing declares infra yet; the
      # check costs nothing and is here so it is not forgotten when something
      # does.
      infra_dir="$HOME/.local/share/catallaxy/infra/$lab"
      if [ -d "$infra_dir" ]; then
        for state in "$infra_dir"/*/*.tfstate; do
          [ -e "$state" ] || continue
          left=$(jq '[.resources[]?] | length' "$state")
          if [ "$left" != "0" ]; then
            echo "teardown left $left resource(s) in $state" >&2
            jq '[.resources[]? | .type + "." + .name]' "$state" >&2
            exit 1
          fi
        done
      fi

      echo "" >&2
      echo "$lab: up in ''${up_seconds}s, verified, idempotent, destroyed clean" >&2
    '';
  };

  all = pkgs.writeShellApplication {
    name = "cata-e2e-all";

    runtimeInputs = [
      one
      pkgs.coreutils
    ];

    text = ''
      set -uo pipefail

      jobs="''${CATA_E2E_JOBS:-2}"

      labs="${labList}"

      if [ "''${1:-}" = "--help" ]; then
        echo "usage: cata-e2e-all [--jobs N]" >&2
        echo "" >&2
        echo "Runs every lab e2e can stand up, N at a time. Each lab is a" >&2
        echo "separate cata-e2e run that asserts its own teardown, so a" >&2
        echo "failure names one lab and the others still finish." >&2
        echo "" >&2
        echo "  --jobs N   labs at once (default $jobs, or CATA_E2E_JOBS)" >&2
        exit 64
      fi

      if [ "''${1:-}" = "--jobs" ]; then
        jobs="''${2:?--jobs needs a number}"
      fi

      outdir=$(mktemp -d)
      trap 'rm -rf "$outdir"' EXIT

      count=$(printf '%s\n' "$labs" | wc -l)
      echo "running $count labs, $jobs at a time" >&2
      echo "" >&2

      # Each lab's output goes to its own file rather than the terminal.
      # Interleaved logs from labs running at once are unreadable, and the one
      # that failed is the one worth printing.
      run_one() {
        lab="$1"
        if cata-e2e "$lab" > "$outdir/$lab.log" 2>&1; then
          echo "  PASS $lab" >&2
          tail -1 "$outdir/$lab.log" >&2
        else
          echo "  FAIL $lab" >&2
          echo "$lab" >> "$outdir/failed"
        fi
      }
      export -f run_one
      export outdir

      printf '%s\n' "$labs" \
        | xargs -P "$jobs" -I{} bash -c 'run_one "$@"' _ {}

      echo "" >&2
      if [ -s "$outdir/failed" ]; then
        while read -r lab; do
          echo "=== $lab ===" >&2
          cat "$outdir/$lab.log" >&2
          echo "" >&2
        done < "$outdir/failed"
        failed=$(wc -l < "$outdir/failed")
        echo "$failed of $count labs failed" >&2
        exit 1
      fi

      echo "all $count labs passed" >&2
    '';
  };
in
{
  packages = {
    e2e = one;
    e2e-all = all;
  };

  apps = {
    e2e = {
      type = "app";
      program = "${one}/bin/cata-e2e";
    };

    e2e-all = {
      type = "app";
      program = "${all}/bin/cata-e2e-all";
    };
  };
}
