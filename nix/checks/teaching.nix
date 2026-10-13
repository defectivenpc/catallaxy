# The template and the authoring guides do not teach ceremony the tree removed.
#
# `consumer-template` builds the template, and a stale template builds fine —
# explicit values still override derived ones, so the old idiom keeps working
# and the check keeps passing. It proves the scaffold is not broken, not that
# it is current.
#
# That gap was not theoretical. Five simplifications landed in a row, each
# scripted over `examples/labs`, and each left `templates/` and the book
# teaching the thing it had just deleted — so a reader following the guide
# would write, by hand, everything the distribution had stopped asking for.
#
# These patterns are decidable, so they are a check rather than a habit.
{ lib, pkgs }:

let
  # taught :: { Pattern -> WhatToSayInstead }
  taught = {
    "cataCharts." = "a floe defaults its own chart; a lab passes none";
    "k8sSpecs." = "a floe defaults its own manifest from the pin";
    "instanceOf = clusterName:" = "the cluster module derives instanceName";
    "instanceName =" = "derived from the lab's name and the attribute path";
    "lab.network.subnet =" = "derived from the lab's name; see lib/allocation.nix";
    "lab.registry.port =" = "derived from the lab's name; see lib/allocation.nix";
    "lab.dns.hostPort =" = "derived from the lab's name; see lib/allocation.nix";
  };

  # Where a newcomer learns the idiom. Not the whole book: a history document
  # or an RFC may quote the old form, and should.
  scanned = [
    ../../templates
    ../../docs/book/src/start-here
    ../../docs/book/src/using
  ];
in
{
  teaching = pkgs.runCommand "teaching-tests" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
    fail=0
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (pattern: instead: ''
        if hits=$(grep -rn --fixed-strings ${lib.escapeShellArg pattern} ${
          lib.concatMapStringsSep " " (p: "${p}") scanned
        } 2>/dev/null); then
          echo "$hits" | sed 's|^|  |' >&2
          echo "    ^ teaches '${pattern}': ${instead}" >&2
          fail=1
        fi
      '') taught
    )}

    if [ "$fail" = 1 ]; then
      echo "" >&2
      echo "The scaffold and the authoring guides are where someone learns what" >&2
      echo "to write. Showing them ceremony the tree no longer asks for is worse" >&2
      echo "than showing them nothing: they will write it, and it will work, and" >&2
      echo "they will not know it was unnecessary." >&2
      exit 1
    fi
    touch $out
  '';
}
