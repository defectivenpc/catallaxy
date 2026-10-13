# Every generated reference page, rendered.
#
# The two halves of the per-module reference meeting one renderer: Nix reads
# the declarations and the links and says what each page *is*;
# `cata-build docs pages` turns that into markdown. One set of escaping rules,
# one answer to what an empty section looks like, and one anchor check — where
# there were three implementations and the floe pages had no check at all.
#
# `path` on each page decides where it lands, so a generator owns its own
# family and adding one needs nothing here.
{
  lib,
  pkgs,
  cata,
  floePages,
  signaturePages,
}:

pkgs.runCommand "reference-pages" { } ''
  mkdir -p $out
  ${cata}/bin/cata-build docs pages ${floePages} $out
  ${cata}/bin/cata-build docs pages ${signaturePages} $out
''
