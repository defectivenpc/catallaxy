# The lowering reads the lab's link through declared channels only.
#
# A lab is one unit of one link, and a floe whose `units` is a link seals
# them: only `exports` crosses, and a lab exports nothing because nothing
# links labs. So `lib/` may read
#
#   `out.<kind>`   the output kinds its units emit, which lift unconditionally
#   `wiring`       which provider filled which hole, which only the linker knows
#   `floeNames`    which floe each unit is an instance of
#
# and not `provides`. Five reads of `provides` used to be there, every one of
# them legal — a parent reading a unit's declared export is the interface
# working. Each is now the thing that holds the fact emitting it: the ingress
# emits the hosts it routes, `lab-delivery` hands each cluster its own answer,
# and the provisioned cluster's descriptor carries the object that makes it.
# ADR 0007.
#
# Checked by grep over `lib/`, because the failure the seal produces is quiet.
# A read of `provides.<cluster>.<name>` that has stopped resolving throws, but
# the lowering writes `or { }` and `or null` everywhere it reads a channel, and
# those default. `lab-routed-hosts-are-claimed` would have passed vacuously
# for every lab.
{ lib, pkgs }:

{
  lab-link-reads =
    pkgs.runCommand "lab-link-reads-tests"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
        lowering = lib.fileset.toSource {
          root = ../..;
          fileset = ../../lib;
        };
      }
      ''
        hits=$(grep -rn 'link\.provides\|link\.out\.provides' "$lowering" \
                 --include='*.nix' \
                 | grep -vE ':[0-9]+:[[:space:]]*#' || true)

        if [ -n "$hits" ]; then
          echo "the lowering reads into the lab's units:" >&2
          echo "$hits" | sed 's/^/  /' >&2
          cat >&2 <<'EOF'

        A lab is a floe whose units are its clusters, the claims that answer
        them, and the floes it holds itself — and an inclusion seals its units'
        `provides`. A lab exports nothing, because nothing links labs, so this
        read resolves to nothing and the `or { }` beside it defaults silently.

        Read it through a channel that crosses instead:

          out.<kind>   have whatever holds the fact emit it. An output kind
                       lifts through the inclusion, keyed by the unit that
                       emitted it — which is the cluster's name when a cluster
                       emitted it, and the contributor's when a collector
                       hands a fan-in back.
          wiring       which provider filled a hole. Not a value: the planner
                       reads `instName` because a plan anchor is keyed by
                       cluster name and no floe has a name for a sibling.

        EOF
          exit 1
        fi

        echo "no reads into the lab's units" > $out
      '';
}
