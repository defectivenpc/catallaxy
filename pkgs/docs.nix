# The book: `docs/book/src` plus the generated floe pages, their index and
# nav, CHANGELOG.md, and the talk decks, spliced in at build time.
{
  lib,
  pkgs,
  talks,
  bookSrc ? ../docs/book,
  floeDocs ? ../docs/generated/floes,
  signatureDocs ? ../docs/generated/signatures,
  optionDocs ? ../docs/generated,
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

  signatureNames = lib.sort (a: b: a < b) (
    lib.filter (n: n != "index") (
      map (lib.removeSuffix ".md") (
        builtins.attrNames (
          lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir signatureDocs)
        )
      )
    )
  );

  # Every page, not just the index: mdBook renders what `SUMMARY.md` lists and
  # nothing else, so an unlisted page is a 404 from the fifty-eight floe pages
  # that link to it. `docs-tests` is what said so.
  signatureNav = lib.concatStringsSep "\n" (
    [ "- [Signatures](./reference/signatures/index.md)" ]
    ++ map (n: "  - [${n}](./reference/signatures/${n}.md)") signatureNames
  );

  index = ''
    # Floes

    One page per floe and per preset, generated from their definitions and —
    for a floe — from an actual link. Each is diff-checked by its own flake
    check.

    Regenerate from `nix build .#referencePages`.

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
    inherit navBlock index signatureNav;
  }
  ''
    cp -r ${bookSrc} book
    chmod -R u+w book

    mkdir -p book/src/reference/floes book/src/reference/signatures
    cp ${floeDocs}/*.md book/src/reference/floes/
    cp "$indexPath" book/src/reference/floes/index.md

    # Every signature, and its own generated index. The floe pages link to
    # these by name, so a missing page here is a broken link on fifty-eight
    # others — which is what `docs-tests` reports.
    cp ${signatureDocs}/*.md book/src/reference/signatures/
    cp ${changelog} book/src/changelog.md

    # mdBook copies anything under `src` that isn't markdown, so a deck
    # lands verbatim at `/talks/<name>/index.html`.
    cp -r --no-preserve=mode ${talks} book/src/talks

    # The option and CLI reference, and the nav that reaches them. The
    # generated SUMMARY is the committed one with those entries spliced in,
    # so it replaces the copy here before the Floes block goes in below.
    cp -r --no-preserve=mode ${optionDocs}/options ${optionDocs}/cli book/src/reference/
    cp --no-preserve=mode ${optionDocs}/SUMMARY.md book/src/SUMMARY.md

    awk -v block="$(cat "$navBlockPath")" -v sigs="$signatureNav" '
      { print }
      /^- \[Floes\]/ { print block; print sigs }
    ' book/src/SUMMARY.md > book/src/SUMMARY.md.new
    mv book/src/SUMMARY.md.new book/src/SUMMARY.md

    grep -q "reference/floes/" book/src/SUMMARY.md || {
      echo "the Floes nav block was not spliced — did the SUMMARY entry move?" >&2
      exit 1
    }

    grep -q "reference/options/steps.md" book/src/SUMMARY.md || {
      echo "the generated option nav is missing — is docs/generated stale?" >&2
      exit 1
    }

    mdbook build book --dest-dir "$out"
  ''
