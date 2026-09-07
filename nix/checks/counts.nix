# A number stated in prose matches the number in the tree.
#
# Written because the floe count appeared in four places with **four
# different values** — 27, 33, 29 and 29 — while the real figure was 37. None
# was a typo; each was true when written, and each was left behind by the next
# floe. A count in prose has no reader that would notice, which is exactly the
# kind of claim a build should be making instead of a person.
#
# Deliberately narrow. It knows two quantities, spelled as digits or as words,
# and it will not learn to parse arbitrary claims:
#
#   "<N> floes"        -> the flattened `floes/default.nix`
#   "<N> example labs" -> the labs that can actually be run
#
# `CHANGELOG.md` and `docs/rfcs/` are not in the source list, on the same rule
# the header check uses: an entry dated last March saying there were 27 floes
# is a true statement about last March, and rewriting it would falsify the
# record.
{
  lib,
  pkgs,
  floeSet,
  labDefs,
}:

let
  # Files whose prose makes claims. Everything else is generated, a dated
  # record, or code the other checks already cover.
  sources = [
    "README.md"
    "floes/default.nix"
    "lib/lab.nix"
    "docs/prior-implementations.md"
  ]
  ++ map (n: "docs/book/src/${n}") [
    "introduction.md"
    "why.md"
    "understanding/model.md"
    "understanding/how-it-works.md"
    "using/configuring.md"
    "using/writing-a-floe.md"
    "reference/options.md"
    "reference/floe-api.md"
    "reference/flake-outputs.md"
    "contributing.md"
    "start-here/first-lab.md"
    "start-here/your-own-lab.md"
    "start-here/next-steps.md"
  ];

  expected = {
    floes = lib.length (lib.attrNames floeSet);
    "example labs" = lib.length (lib.attrNames labDefs);
  };
in
{
  counts =
    pkgs.runCommand "counts-tests"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions (map (p: ../.. + "/${p}") sources);
        };
        expected = builtins.toJSON expected;
        passAsFile = [ "expected" ];
      }
      ''
        python3 ${./counts.py} "$expectedPath" "$src" > $out
      '';
}
