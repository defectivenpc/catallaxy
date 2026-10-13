# What each floe's interface says, pinned.
#
# The finest-grained regression net in the tree. A manifest digest says "this
# lab renders something different"; this says "this floe's outward surface
# changed, and here is the line". That is what makes a refactor across 37 files
# provable rather than hopeful: a change that means to alter nothing must move
# nothing here.
#
# It also covers what nothing else does. `manifest-digest` walks rendered YAML,
# so it cannot see an ops command's name, a bundle's ready-probe kind, whether a
# provision's field travels or is link-local, or that a floe adds a plan step.
# All of those reach an operator or another floe, and all of them were
# previously checked by nobody.
#
# Diffed against `nix/floe-docs.nix` rather than recomputed, so this and
# `refresh-docs` read one store path instead of two pipelines that can
# disagree — the same construction `cliConfig-<lab>` uses.
{
  lib,
  pkgs,
  referencePages,
  docDir,
  floeSet,
}:

{
  # Every floe is rendered by some lab, so every page says what the floe does
  # and not only what it declares.
  #
  # A page with nothing linked to read is honest, and it is also half a page:
  # the declaration is the floe's promise and the emission is what keeping it
  # looks like. `floe-gates` already refuses a floe with no isolation suite;
  # this refuses one no lab places, which is the other way a floe goes
  # unexercised.
  #
  # It fires on the grep rather than on a Nix-side list because the note is
  # what a reader sees, and the note is what has been wrong: thirteen pages
  # carried it about floes every lab in the tree renders, because `placement`
  # looked only inside clusters and a host floe is a unit of the lab.
  floe-pages-are-rendered =
    pkgs.runCommand "floe-pages-are-rendered" { nativeBuildInputs = [ pkgs.gnugrep ]; }
      ''
        unrendered=$(grep -l 'No lab in this tree renders this floe' ${referencePages}/floes/*.md || true)

        if [ -n "$unrendered" ]; then
          echo "floe(s) no lab in this tree renders:" >&2
          for f in $unrendered; do
            echo "  $(basename "$f" .md)" >&2
          done
          echo "" >&2
          echo "Each gets a declaration section and an honest note instead of an" >&2
          echo "emitted interface, so half its page is missing. Place it in a lab —" >&2
          echo "\`examples/labs/tests/every-floe.nix\` is the one built to hold" >&2
          echo "whatever has nowhere else to go — or delete the floe." >&2
          exit 1
        fi

        echo "${toString (lib.length (lib.attrNames floeSet))} floe pages, all rendered by some lab" > $out
      '';
}
// lib.foldl' lib.mergeAttrs { } (
  map (name: {
    "floe-interface-${name}" =
      pkgs.runCommand "floe-interface-${name}" { nativeBuildInputs = [ pkgs.diffutils ]; }
        ''
          if ! diff -u ${docDir}/${name}.md ${referencePages}/floes/${name}.md; then
            echo "" >&2
            echo "The interface of '${name}' changed." >&2
            echo "" >&2
            echo "This is the floe as anything outside it sees it: what a deployer" >&2
            echo "may set, what it asks the cluster for, what it provides and which" >&2
            echo "of those fields travel, what installs and in what order, and what" >&2
            echo "an operator can type. A change here is a change to somebody else's" >&2
            echo "contract, whether or not any manifest moved." >&2
            echo "" >&2
            echo "If intended, refresh it and read the diff:" >&2
            echo "" >&2
            echo "  nix run .#refresh-docs" >&2
            exit 1
          fi
          touch $out
        '';
  }) (lib.attrNames floeSet)
)
