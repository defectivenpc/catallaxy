# Everything built for a reader: the book, the talk decks, and the reference
# pages generated into it.
#
#   docs = import ./nix/docs { inherit lib pkgs cata catallaxy mkFloes floeSet labDefs; };
#
#   docs.book            => the mdBook site, `nix build .#docs`
#   docs.talks           => one reveal.js deck per `docs/talks/*.md`
#   docs.optionDocs      => the option and CLI reference, as committed under docs/generated
#   docs.referencePages  => the floe, signature and kind pages, as committed under docs/generated
{
  lib,
  pkgs,
  cata,
  catallaxy,
  mkFloes,
  floeSet,
  labDefs,
}:

let
  page = import ./page.nix { inherit lib pkgs; };

  pageArgs = {
    inherit
      lib
      page
      catallaxy
      mkFloes
      floeSet
      ;
  };

  talks = import ./talks.nix { inherit lib pkgs; };
in
{
  inherit talks;

  book = import ./book.nix { inherit lib pkgs talks; };

  optionDocs = import ./option-docs.nix {
    inherit lib pkgs cata;
    optionsJSON = import ./options-json.nix { inherit lib pkgs; };
  };

  referencePages = import ./reference-pages.nix {
    inherit lib pkgs cata;
    floePages = import ./floes.nix (pageArgs // { inherit labDefs; });
    kindPages = import ./kinds.nix pageArgs;
    signaturePages = import ./signatures.nix pageArgs;
  };
}
