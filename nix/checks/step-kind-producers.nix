# Every step kind the tree declares is emitted by something, or is listed
# here as a known orphan with a reason.
#
# `modules/lab/planner/kinds/` declares what a plan step may be, and the CLI
# implements every one. A kind nothing emits is a claim the tree makes and
# cannot honour: the CLI carries code for a step no lab can ever contain, and
# a reader finds a documented capability with no way to reach it.
#
# This was prose before, in `docs/prior-implementations.md`, and it drifted
# both ways at once — it named `sync-kubeconfig`,
# `release-cluster-cloud-resources` and `{reconcile,delete}-managed-resource`
# as orphaned when all four are emitted, and missed `trust-bundle` and
# `verify-argocd-reachable`, which are not. The list is mechanically
# decidable, so it should not have been prose.
#
# "Emitted" means named as a `kind` somewhere outside the declaration itself:
# by `modules/lab/plan.nix`, by the planner, or by a floe — `run-script` is
# emitted by `floes/cluster/external-dns/`, which is why a search of
# `modules/` alone gets this wrong.
#
# The weaker question — which kinds appear in a *rendered* plan — is answered
# by the plan snapshots, and differs: `dns-setup` has a producer but no
# current lab enables it. That is an example lab's coverage, not a hole in
# the tree, and conflating the two is what made the prose wrong.
{ lib, pkgs }:

let
  declared = lib.sort (a: b: a < b) (
    map (lib.removeSuffix ".nix") (
      lib.filter (n: n != "default.nix") (
        builtins.attrNames (
          lib.filterAttrs (_: t: t == "regular") (builtins.readDir ../../modules/lab/planner/kinds)
        )
      )
    )
  );

  # Each orphan, with why it has no producer. An entry is a debt that has
  # been looked at, not a way past the check — which is the whole difference
  # between this and deleting the check.
  orphans = {
    bootstrap-argocd-helm = "the Helm path to ArgoCD; `bootstrap-argocd-kubectl-ssa` is what the argocd floe emits";
    colima-network-route = "a macOS-only route into the Colima VM; nothing declares it since the host services were rewritten";
    host-trust-install = "installing the lab CA into the host trust store; the ops command that did this went with the parked tree";
    pivot = "moving a cloud cluster's control off the bootstrap cluster — the Crossplane half, never rebuilt";
    publish-images = "pushing a lab's images to its registry; `warm-cache` covers the read path only";
    trust-bundle = "distributing the lab CA as a step; trust-manager does it in-cluster instead";
    verify-argocd-reachable = "a bespoke readiness step; a bundle's `ready` probe covers it";
  };
in
{
  step-kind-producers =
    pkgs.runCommand "step-kind-producers-tests"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
        # Everything that could name a kind, and nothing that merely declares
        # or implements one.
        producers = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../modules/lab/plan.nix
            ../../modules/lab/cd.nix
            ../../modules/lab/secrets.nix
            ../../modules/lab/planner/provisions.nix
            ../../lib/floe-catallaxy
            ../../floes
            ../../examples/labs
          ];
        };
        declared = lib.concatStringsSep "\n" declared;
        known = lib.concatStringsSep "\n" (lib.attrNames orphans);
        passAsFile = [
          "declared"
          "known"
        ];
      }
      ''
        unproduced=""
        while read -r kind; do
          [ -n "$kind" ] || continue
          if ! grep -rqF -- "\"$kind\"" "$producers"; then
            unproduced="$unproduced$kind"$'\n'
          fi
        done < "$declaredPath"

        # `comm` needs both sides sorted; both are, `declared` by construction
        # and `known` because Nix attribute names are.
        surprises=$(comm -23 <(printf '%s' "$unproduced" | sort -u | grep -v '^$') "$knownPath" || true)
        resolved=$(comm -13 <(printf '%s' "$unproduced" | sort -u | grep -v '^$') "$knownPath" || true)

        status=0

        if [ -n "$surprises" ]; then
          echo "step kind(s) nothing emits, and not listed as known orphans:" >&2
          echo "$surprises" | sed 's/^/  /' >&2
          echo "" >&2
          echo "The CLI implements this kind and no lab can contain it. Either" >&2
          echo "emit it, delete it, or add it to \`orphans\` in" >&2
          echo "nix/checks/step-kind-producers.nix with a line saying why." >&2
          status=1
        fi

        if [ -n "$resolved" ]; then
          echo "step kind(s) listed as orphaned that something now emits:" >&2
          echo "$resolved" | sed 's/^/  /' >&2
          echo "" >&2
          echo "Good news, and the list has to say so — an orphan list that" >&2
          echo "keeps naming resolved entries stops being read." >&2
          status=1
        fi

        [ "$status" = 0 ] || exit 1
        echo "${toString (lib.length declared)} step kinds, ${toString (lib.length (lib.attrNames orphans))} orphaned and accounted for" > $out
      '';
}
