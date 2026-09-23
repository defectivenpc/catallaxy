# Every `docs/talks/*.md` built into a self-contained reveal.js deck, one
# directory per talk, named after the file. Open `<name>/index.html`; it
# needs no network, so it presents from a laptop with the wifi off.
#
#     nix build .#talks && xdg-open result/floes-lightning/index.html
#
# The same tree is spliced into the book under `/talks/`, so a deck is
# published by adding a markdown file here and nothing else.
{
  lib,
  pkgs,
  talkSrc ? ../docs/talks,
}:

let
  names = lib.sort (a: b: a < b) (
    map (lib.removeSuffix ".md") (
      builtins.attrNames (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir talkSrc)
      )
    )
  );

  # reveal-md resolves `--static-dirs` relative to the markdown file, so the
  # source has to sit in the build directory or the copy escapes the output.
  build = n: ''
    cp ${talkSrc}/${n}.md .
    reveal-md ${n}.md --static "$out/${n}" --static-dirs=assets
  '';
in
pkgs.runCommand "catallaxy-talks"
  {
    nativeBuildInputs = [ pkgs.reveal-md ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME" assets "$out"
    ${lib.concatMapStringsSep "\n" build names}
  ''
