# The book: `docs/book/src` plus the generated floe pages, their index and
# nav, and CHANGELOG.md, spliced in at build time.
{
  lib,
  pkgs,
  bookSrc ? ../docs/book,
  floeDocs ? ../docs/floes,
  changelog ? ../CHANGELOG.md,
}:

let
  # floeNames :: [String]
  floeNames = lib.sort (a: b: a < b) (
    map (lib.removeSuffix ".md") (
      builtins.attrNames (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir floeDocs)
      )
    )
  );

  navBlock = lib.concatMapStringsSep "\n" (n: "  - [${n}](./reference/floes/${n}.md)") floeNames;

  index = ''
    # Floes

    One page per floe, generated from the floe definitions and from an actual
    link. Each is diff-checked by its own flake check.

    Regenerate with `nix run .#refresh-floe-docs`.

    ${lib.concatMapStringsSep "\n" (n: "- [${n}](./${n}.md)") floeNames}
  '';
in
pkgs.runCommand "catallaxy-book"
  {
    nativeBuildInputs = [ pkgs.mdbook ];
    passAsFile = [
      "navBlock"
      "index"
    ];
    inherit navBlock index;
  }
  ''
    cp -r ${bookSrc} book
    chmod -R u+w book

    mkdir -p book/src/reference/floes
    cp ${floeDocs}/*.md book/src/reference/floes/
    cp "$indexPath" book/src/reference/floes/index.md
    cp ${changelog} book/src/changelog.md

    awk -v block="$(cat "$navBlockPath")" '
      { print }
      /^- \[Floes\]/ { print block }
    ' book/src/SUMMARY.md > book/src/SUMMARY.md.new
    mv book/src/SUMMARY.md.new book/src/SUMMARY.md

    grep -q "reference/floes/" book/src/SUMMARY.md || {
      echo "the Floes nav block was not spliced — did the SUMMARY entry move?" >&2
      exit 1
    }

    mdbook build book --dest-dir "$out"
  ''
