# The book builds, and every link inside it resolves.
#
# Two failures this catches, and both had already happened to this book once:
#
#   - A `SUMMARY.md` entry naming a page that does not exist. `book.toml` sets
#     `create-missing = false`, so mdbook errors rather than writing the blank
#     page it would otherwise render, and this turns that into a red check.
#   - A relative link from one page to another that has moved or been renamed.
#     mdbook does not check these — a `[Write a Floe](./writing-a-floe.md)`
#     pointing at nothing renders as a link and 404s for the reader. So the
#     second half of this walks the built HTML.
#
# The book is *assembled* by `pkgs/docs.nix`, which splices in the generated
# per-floe pages. Building it here rather than checking the source directory
# means the check covers the spliced result, which is what a reader gets.
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
