# What each signature's interface says, pinned.
#
# The same net as `floe-interface-<name>`, one level up. A floe page says what
# that floe promises; a signature page says what every floe promising it has
# agreed to, and which ones those are — which is derived from the whole set, so
# a floe gaining or losing a hole moves a page it does not contain.
#
# That is the point of pinning it. A floe's own page moving is a change to its
# contract; a signature page moving is a change to *who* is on the other end of
# one, and nothing else in the tree reports that.
{
  lib,
  pkgs,
  referencePages,
  docDir,
  catallaxy,
}:

lib.foldl' lib.mergeAttrs { } (
  map (name: {
    "signature-interface-${name}" =
      pkgs.runCommand "signature-interface-${name}" { nativeBuildInputs = [ pkgs.diffutils ]; }
        ''
          if ! diff -u ${docDir}/${name}.md ${referencePages}/signatures/${name}.md; then
            echo "" >&2
            echo "The interface of '${name}' changed." >&2
            echo "" >&2
            echo "Either the signature itself moved — a field, its description, the" >&2
            echo "canonical name every provider must use — or the set of floes on" >&2
            echo "either end of it did. Both are somebody else's contract: a floe" >&2
            echo "resolving this reads the fields, and a floe providing it is what" >&2
            echo "another floe's hole resolves to." >&2
            echo "" >&2
            echo "If intended, refresh it and read the diff:" >&2
            echo "" >&2
            echo "  nix run .#refresh-docs" >&2
            exit 1
          fi
          touch $out
        '';
  }) (lib.attrNames catallaxy.sigs)
  ++ [
    {
      signature-index = pkgs.runCommand "signature-index" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
        if ! diff -u ${docDir}/index.md ${referencePages}/signatures/index.md; then
          echo "" >&2
          echo "The signature index is stale — a signature was added or removed." >&2
          echo "  nix run .#refresh-docs" >&2
          exit 1
        fi
        touch $out
      '';
    }
  ]
)
