# The book.
#
# The source under `docs/book/src` is hand-written, and three things are
# spliced in at build time rather than committed:
#
#   - the 37 per-floe pages from `docs/floes/`, which `nix/floe-docs.nix`
#     generates and 37 flake checks diff. Copying them here means the book
#     cannot show a stale interface: the page it renders is the page the check
#     compares, or the build that produced it already failed.
#   - an index over those pages, and their `SUMMARY.md` nav entries. Both are
#     derived from the file list, so adding a floe adds a page and a nav entry
#     with no edit to anything. "Added a floe, forgot the nav entry" was a
#     class of failure the previous book had a whole second check for.
#   - `CHANGELOG.md` from the repo root, so the book links the real one rather
#     than a copy that drifts.
#
# mdbook fails on a `SUMMARY.md` entry with no file, which is what makes
# `checks.docs` worth having: it turns a dead link into a failed build.
{
  lib,
  pkgs,
  bookSrc ? ../docs/book,
  floeDocs ? ../docs/floes,
  changelog ? ../CHANGELOG.md,
}:

let
  floeNames = lib.sort (a: b: a < b) (
    map (lib.removeSuffix ".md") (
      builtins.attrNames (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir floeDocs)
      )
    )
  );

  # Indented two spaces so mdbook nests them under the `Floes` entry.
  navBlock = lib.concatMapStringsSep "\n" (n: "  - [${n}](./reference/floes/${n}.md)") floeNames;

  index = ''
    # Floes

    One page per floe, generated from the floe definitions and from an actual
    link — so the declaration half comes from the definition and the "what it
    emits" half from linking it for real. Each is diff-checked by its own
    flake check.

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

    # Insert the per-floe nav under the `Floes` entry. `awk` rather than
    # `sed`, because the block is multi-line and holds `[`, `]` and `/`.
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
