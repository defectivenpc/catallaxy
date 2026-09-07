{
  lib,
  pkgs,
  craneLib,
  rustToolchain,
}:

let
  cliSrc = lib.cleanSourceWith {
    src = ../cli;
    filter =
      path: type:
      (craneLib.filterCargoSources path type)
      || (type == "directory")
      || (
        lib.any (ext: lib.hasSuffix ext path) [
          ".json"
          ".crt"
          ".key"
        ]
        && lib.hasInfix "/tests/fixtures/" path
      )
      || (lib.hasSuffix ".nix" path && lib.hasInfix "/src/commands/templates/" path)
      # The I/O boundary test's baseline. Without it the test panics rather
      # than passing, which is the right way round, but it has to be here.
      || (lib.hasSuffix ".txt" path && lib.hasInfix "/tests/" path);
  };

  # The book's source, for `cli/tests/book.rs` — every `cata` command a page
  # prints has to be one the parser accepts, and the parser is here.
  #
  # Passed as an environment variable rather than by widening `src` to the
  # repo root, which would rebuild the CLI on any change anywhere. It is set
  # on `buildPackage` only and not on `commonArgs`, so `buildDepsOnly`'s
  # artifacts are unaffected: editing a page recompiles the crate from cached
  # dependencies rather than from nothing.
  bookSrc = ../docs/book/src;

  commonArgs = {
    src = cliSrc;
    strictDeps = true;
    buildInputs =
      [ ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        pkgs.libiconv
        pkgs.apple-sdk
      ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    CATALLAXY_BOOK_SRC = bookSrc;

    passthru.clippy = craneLib.cargoClippy (
      commonArgs
      // {
        inherit cargoArtifacts;
        cargoClippyExtraArgs = "--all-targets -- --deny warnings";
      }
    );
  }
)
