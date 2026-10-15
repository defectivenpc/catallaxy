# Every name `lib/` exports, something reads.
#
# `lib/` is this repo's own core, not a published library — the published one
# is `floes`. So a name with no reader is not a surface held for somebody
# else; it is a surface held for nobody, and it constrains the implementation
# anyway, because the next caller is entitled to use it.
#
# It found 32, of which four were dead outright — including a 110-line
# submodule type whose doc comment described two callers it did not have.
#
# Greps rather than resolves, so `x.name` and `inherit (m) name` both count,
# and so does a mention in `docs/` — a documented name is an intended surface
# even with no caller yet.
#
# Loose in one direction only: a name that coincides with a word used
# elsewhere reads as live. Tightening that would need a Nix parser, and the
# check is worth more than the last few percent of it.
{
  lib,
  pkgs,
}:

let
  # name -> why nothing reads it. In this file rather than at the call site
  # because the search excludes this file: an entry naming a symbol would
  # otherwise be a reader of it, and every exemption would resolve itself.
  unread = {
    "lib/floe-catallaxy/default.nix: clusterFrame" =
      "the distribution's own `rec` set, where a frame reads as public whether or not a second kind of floe uses one yet";

    "lib/floe-catallaxy/default.nix: clusterSecurityInputs" =
      "the same: what every cluster asks of its namespaces is part of the surface, and `clusterFrame` is its only caller";
  };

  tree = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../lib
      ../../floes
      ../../nix
      ../../pkgs
      ../../examples
      ../../cli/src
      ../../flake.nix
      (lib.fileset.difference ../../docs ../../docs/generated)
    ];
  };
in
{
  lib-exports =
    pkgs.runCommand "lib-exports"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.gnused
          pkgs.findutils
        ];
        inherit tree;
        known = lib.concatStringsSep "\n" (lib.attrNames unread);
        passAsFile = [ "known" ];
      }
      ''
        cd "$tree"

        # Everything declared at indent two after the module's final `in`,
        # which is where a module's exports sit. A file with no `in` is all
        # exports.
        exports() {
          local f="$1" start
          start=$(grep -n '^in$' "$f" | tail -1 | cut -d: -f1)
          sed -n "''${start:-1},\$p" "$f" \
            | grep -oE '^  (inherit\b[^;]*;|[a-zA-Z][A-Za-z0-9_'"'"']* =)' \
            | sed -e 's/^  //' -e 's/ =$//' -e 's/^inherit *(.*)//' -e 's/^inherit //' -e 's/;$//' \
            | tr ' ' '\n' \
            | grep -xE "[a-zA-Z][A-Za-z0-9_']*" \
            | grep -vxE 'inherit|lib|pkgs'
        }

        unread=""
        for f in $(find lib -name '*.nix' -not -path '*/generated/*' -not -path 'lib/tests/*'); do
          for n in $(exports "$f" | sort -u || true); do
            readers=$(grep -rlE "(^|[^A-Za-z0-9_'])$n([^A-Za-z0-9_']|\$)" \
                        --include='*.nix' --include='*.rs' --include='*.md' \
                        --exclude-dir=generated --exclude-dir=crds \
                        --exclude=lib-exports.nix . 2>/dev/null \
                      | grep -vx "./$f" || true)
            [ -n "$readers" ] || unread="$unread$f: $n"$'\n'
          done
        done

        printf '%s' "$unread" | sed '/^$/d' | sort -u > "$TMPDIR/unread"
        sed '/^$/d' "$knownPath" | sort -u > "$TMPDIR/known"

        surprises=$(comm -23 "$TMPDIR/unread" "$TMPDIR/known" || true)
        resolved=$(comm -13 "$TMPDIR/unread" "$TMPDIR/known" || true)

        status=0

        if [ -n "$surprises" ]; then
          echo "lib/ exports a name nothing reads:" >&2
          echo "$surprises" | sed 's/^/  /' >&2
          echo "" >&2
          echo "Move it into the \`let\` above the returned set, delete it, or" >&2
          echo "record why in \`unread\` in nix/checks/lib-exports.nix." >&2
          status=1
        fi

        if [ -n "$resolved" ]; then
          echo "these are listed as unread and now have a reader:" >&2
          echo "$resolved" | sed 's/^/  /' >&2
          echo "Drop the entry." >&2
          status=1
        fi

        [ "$status" = 0 ] || exit 1
        wc -l < "$TMPDIR/known" | sed 's/$/ unread export(s), each accounted for/' > $out
      '';
}
