# "<N> floes" and "<N> example labs" in prose match the tree.
#
# CHANGELOG.md and docs/rfcs/ are not sources: a dated entry's count was true
# when written.
{
  lib,
  pkgs,
  floeSet,
  labDefs,
}:

let
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

  # expected :: { Subject -> Int }
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
