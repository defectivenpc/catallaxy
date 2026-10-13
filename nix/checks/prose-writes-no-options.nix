# No document writes to a lab option tree, because there is no longer one.
#
# A lab is a floe: what varies arrives as an input at the instantiation site,
# so `lab.name = …` and `lab.clusters.app.floe = …` are not stale spellings of
# something — they are a surface that does not exist. A reader who copies one
# gets "The option `lab.name' does not exist", and the book is the first thing
# anybody reads.
#
# Decidable, which is why it is a check rather than a sweep. Reading a field
# off the record `mkLab` returns is still right — `lab.cliConfig`,
# `lab.package` — so the pattern is the *assignment*, and nothing in the new
# shape assigns one.
#
# History documents are exempt by name. `CHANGELOG.md` and `docs/adr/` record
# what was true when they were written, and rewriting them to match the
# present is how a decision record stops being one.
{ lib, pkgs }:

let
  prose = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../docs/book/src
      ../../README.md
      ../../CONTEXT.md
    ];
  };
in
{
  prose-writes-no-options =
    pkgs.runCommand "prose-writes-no-options"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        cd ${prose}

        if hits=$(grep -rnE '(^|[^a-zA-Z.])lab\.[a-zA-Z][a-zA-Z0-9.<>-]* *=' . 2>/dev/null); then
          echo "$hits" | sed 's/^/  /' >&2
          cat >&2 <<'EOF'

        A lab is a floe. There is no option tree to assign to: what an
        environment varies is an input, passed where the lab is instantiated.

          lab.name = "minimal.local";            ->  labs.minimal { name = "minimal.local"; }
          lab.units.proxy = floes.lab-proxy { };  ->  units.proxy = floes.lab-proxy { };
          lab.clusters.app.floe = …;              ->  clusters = _: { app = { floe = …; … }; };

        `examples/labs/minimal/` is the worked example, and it is built by CI.

        Reading the record `mkLab` returns is not this: `lab.cliConfig` and
        `lab.package` are fields of a value, not options.
        EOF
          exit 1
        fi

        echo "no document writes to a lab option tree" > $out
      '';
}
