# The address plan, written down.
#
# An address plan is a decision and must be written once. This
# is where it is written. `lib/allocation.nix` derives it from the lab's name;
# this records the result, and `checks.allocations` refuses a tree where the
# two disagree.
#
# That is what keeps the derivation honest. A lab renamed is a lab reallocated,
# and without this the move would be silent — which is the one thing §5's
# reason could not tolerate. Here it is a line in a reviewed diff.
{
  lib,
  pkgs,
  labDefs,
}:

let
  alloc = import ../lib/allocation.nix { inherit lib; };

  # Keyed by every lab the tree builds, so a lab added or renamed moves a line
  # here. The values come from `allocationFor` and not from the labs, which is
  # what the header claims and was not true: it read five options back, and
  # every one of their defaults was this same expression.
  #
  # What this does not catch is a lab publishing a port outside its slot. That
  # is `lab-checks`' port-clash check, which reads the ports the host services
  # actually publish — the place an override would bite.
  table = lib.mapAttrs (
    labName: _:
    {
      slot = alloc.slotOf labName;
    }
    // alloc.allocationFor labName
  ) labDefs;
in
pkgs.runCommand "allocations" { } ''
  mkdir -p $out
  cp ${pkgs.writeText "allocations.json" (builtins.toJSON table)} $out/allocations.json
  ${pkgs.jq}/bin/jq -S . $out/allocations.json > $out/sorted.json
  mv $out/sorted.json $out/allocations.json
''
