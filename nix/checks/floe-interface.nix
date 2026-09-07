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
# promise's field travels or is link-local, or that a floe adds a plan step.
# All of those reach an operator or another floe, and all of them were
# previously checked by nobody.
#
# Diffed against `nix/floe-interface.nix` rather than recomputed, so this and
# `refresh-floe-docs` read one store path instead of two pipelines that can
# disagree — the same construction `cliConfig-<lab>` uses.
{
  lib,
  pkgs,
  floeInterfaces,
  docDir,
  floeSet,
}:

lib.foldl' lib.mergeAttrs { } (
  map (name: {
    "floe-interface-${name}" =
      pkgs.runCommand "floe-interface-${name}" { nativeBuildInputs = [ pkgs.diffutils ]; }
        ''
          if ! diff -u ${docDir}/${name}.md ${floeInterfaces}/${name}.md; then
            echo "" >&2
            echo "The interface of '${name}' changed." >&2
            echo "" >&2
            echo "This is the floe as anything outside it sees it: what a deployer" >&2
            echo "may set, what it asks the cluster for, what it promises and which" >&2
            echo "of those fields travel, what installs and in what order, and what" >&2
            echo "an operator can type. A change here is a change to somebody else's" >&2
            echo "contract, whether or not any manifest moved." >&2
            echo "" >&2
            echo "If intended, refresh it and read the diff:" >&2
            echo "" >&2
            echo "  nix run .#refresh-floe-docs" >&2
            exit 1
          fi
          touch $out
        '';
  }) (lib.attrNames floeSet)
)
