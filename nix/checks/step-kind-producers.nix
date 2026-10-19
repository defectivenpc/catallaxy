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
    lib.attrNames (import ../../lib/step-kinds.nix { inherit lib; })
  );

  # orphans :: { KindName -> Why }
  #
  # Empty, and worth keeping as a surface. `pivot` and `publish-images` lived
  # here and are deleted: an executor whose params nothing has ever
  # constructed has never run and cannot, so it is not a head start. Both are
  # better re-added with the producer that needs them, where the params can be
  # shaped by something that actually fills them.
  orphans = { };
in
{
  step-kind-producers =
    pkgs.runCommand "step-kind-producers-tests"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
        producers = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../lib/lower/plan.nix
            ../../lib/lower/plan-provisions.nix
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

        # Through files rather than process substitution, and with blank lines
        # stripped on both sides: `printf '%s\n' ""` on an empty list hands
        # `comm` one blank line, which it duly reports as a difference. With no
        # orphans left that was the whole of the output.
        printf '%s' "$unproduced" | sort -u | sed '/^$/d' > "$TMPDIR/unproduced"
        sed '/^$/d' "$knownPath" | sort -u > "$TMPDIR/known"

        surprises=$(comm -23 "$TMPDIR/unproduced" "$TMPDIR/known" || true)
        resolved=$(comm -13 "$TMPDIR/unproduced" "$TMPDIR/known" || true)

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
