# The committed address plan matches what the lab names derive.
#
# An address plan has to be written down. It is derived now rather than
# chosen, so this is what "written down" means: a rename reallocates a lab, and
# the move appears here as a reviewed line rather than happening quietly.
{
  lib,
  pkgs,
  allocations,
}:

{
  allocations = pkgs.runCommand "allocations-check" { } ''
    if ! diff -u ${../../examples/labs/tests/allocations.json} ${allocations}/allocations.json > $TMPDIR/diff; then
      cat $TMPDIR/diff >&2
      echo "" >&2
      echo "The committed address plan is stale." >&2
      echo "" >&2
      echo "Every host port and subnet is derived from the lab's name, so this" >&2
      echo "diff is a lab being renamed, added, or removed. Read it: a lab that" >&2
      echo "moved has moved for whoever had its port in a bookmark." >&2
      echo "" >&2
      echo "  nix build .#allocations   # then copy allocations.json over the committed one" >&2
      exit 1
    fi
    touch $out
  '';
}
