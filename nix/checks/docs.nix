# The book builds and every internal link resolves.
#
# Runs against the assembled book, so the spliced floe pages are covered.
{
  lib,
  pkgs,
  docs,
}:

{
  docs = pkgs.runCommand "docs-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${./docs-links.py} ${docs} > $out
  '';
}
