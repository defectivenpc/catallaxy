# Every step kind is emitted by something, or listed in `orphans` with a
# reason. Fails both ways: an unlisted kind nothing emits, and a listed kind
# something now emits.
#
# Emitted means named as a `kind` outside its own declaration — by the lab,
# the planner, or a floe.
{ lib, pkgs }:

let
  # declared :: [KindName]
  declared = lib.sort (a: b: a < b) (
    map (lib.removeSuffix ".nix") (
      lib.filter (n: n != "default.nix") (
        builtins.attrNames (
          lib.filterAttrs (_: t: t == "regular") (builtins.readDir ../../modules/lab/planner/kinds)
        )
      )
    )
  );

  # orphans :: { KindName -> Why }
  orphans = {
    bootstrap-argocd-helm = "the Helm path to ArgoCD; the argocd floe emits `bootstrap-argocd-kubectl-ssa`";
    colima-network-route = "a macOS-only route into the Colima VM; nothing declares it since the host services were rewritten";
    host-trust-install = "installing the lab CA into the host trust store; its ops command went with the parked tree";
    pivot = "moving a cloud cluster's control off the bootstrap cluster; the Crossplane half, never rebuilt";
    publish-images = "pushing a lab's images to its registry; `warm-cache` covers the read path only";
    trust-bundle = "distributing the lab CA as a step; trust-manager does it in-cluster";
    verify-argocd-reachable = "a bespoke readiness step; a bundle's `ready` probe covers it";
  };
in
{
  step-kind-producers =
    pkgs.runCommand "step-kind-producers-tests"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
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

        sorted=$(printf '%s' "$unproduced" | sort -u | grep -v '^$')
        surprises=$(comm -23 <(printf '%s\n' "$sorted") "$knownPath" || true)
        resolved=$(comm -13 <(printf '%s\n' "$sorted") "$knownPath" || true)

        status=0

        if [ -n "$surprises" ]; then
          echo "step kind(s) nothing emits, and not listed as orphans:" >&2
          echo "$surprises" | sed 's/^/  /' >&2
          echo "Emit it, delete it, or add it to \`orphans\` with a reason." >&2
          status=1
        fi

        if [ -n "$resolved" ]; then
          echo "step kind(s) listed as orphaned that something now emits:" >&2
          echo "$resolved" | sed 's/^/  /' >&2
          echo "Drop the entry." >&2
          status=1
        fi

        [ "$status" = 0 ] || exit 1
        echo "${toString (lib.length declared)} step kinds, ${toString (lib.length (lib.attrNames orphans))} orphaned and accounted for" > $out
      '';
}
