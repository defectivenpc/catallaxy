{ lib }:

let
  hexDigits = lib.listToAttrs (
    lib.imap0 (i: c: lib.nameValuePair c i) (lib.stringToCharacters "0123456789abcdef")
  );

  fromHex = s: lib.foldl' (acc: c: acc * 16 + hexDigits.${c}) 0 (lib.stringToCharacters s);
  slotOf =
    labName: lib.mod (fromHex (builtins.substring 0 6 (builtins.hashString "sha256" labName))) 256;

  subnetOfSlot = slot: "172.${toString (16 + slot / 16)}.${toString ((lib.mod slot 16) * 16)}.0/20";

  portsOfSlot = slot: {
    egress = 3000 + slot;
    registry = 5000 + slot;
    dns = 5300 + slot;
    proxyHttp = 8000 + slot;
    proxyHttps = 8400 + slot;
  };

in
{
  allocationFor =
    labName:
    let
      slot = slotOf labName;
    in
    { subnet = subnetOfSlot slot; } // portsOfSlot slot;
}
