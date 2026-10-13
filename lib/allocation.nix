# What a lab is allocated on the host it shares with every other lab.
#
# Subnets and host ports are scarce and shared, so an address
# plan is a decision and must be written down. It is — in
# `examples/labs/tests/allocations.json`, generated from this and diff-checked.
# What §5 asked for is that a plan be visible and stable, not that a person
# choose the numbers: choosing by hand meant nine env files carrying 43
# literals, a collision on every merge of two branches that each added a lab,
# and a failure naming two labs neither author owned.
#
# One slot per lab decides everything. Two labs either collide on all of it or
# on none, which is what makes a collision obvious rather than partial, and
# `lab-checks` refuses one and names a free slot.
{ lib }:

let
  hexDigits = lib.listToAttrs (
    lib.imap0 (i: c: lib.nameValuePair c i) (lib.stringToCharacters "0123456789abcdef")
  );

  fromHex = s: lib.foldl' (acc: c: acc * 16 + hexDigits.${c}) 0 (lib.stringToCharacters s);

  # slotOf :: LabName -> 0..255
  slotOf =
    labName: lib.mod (fromHex (builtins.substring 0 6 (builtins.hashString "sha256" labName))) 256;
in
rec {
  inherit slotOf;

  # 256 non-overlapping /20s inside 172.16.0.0/12, which is the whole of the
  # RFC 1918 middle block. The hand-picked values had drifted out of it —
  # 172.33 and up are public address space, and a lab claiming them works
  # until something on the host wants to reach the real owner.
  subnetOfSlot = slot: "172.${toString (16 + slot / 16)}.${toString ((lib.mod slot 16) * 16)}.0/20";

  # One base per service, 256 apart, so a slot never lands in another
  # service's range.
  portsOfSlot = slot: {
    egress = 3000 + slot;
    registry = 5000 + slot;
    dns = 5300 + slot;
    proxyHttp = 8000 + slot;
    proxyHttps = 8400 + slot;
  };

  # allocationFor :: LabName -> { subnet; egress; registry; dns; proxyHttp; proxyHttps }
  allocationFor =
    labName:
    let
      slot = slotOf labName;
    in
    { subnet = subnetOfSlot slot; } // portsOfSlot slot;
}
