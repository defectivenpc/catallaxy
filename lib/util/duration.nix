# Duration strings (`3m`, `10m`, `1h`) to seconds.
{ lib }:

let
  inherit (import ./parse.nix { inherit lib; }) toIntOrNull;

  # Seconds per unit. Adding a unit here is the whole change; nothing else
  # enumerates them.
  unitSeconds = {
    s = 1;
    m = 60;
    h = 3600;
    d = 86400;
  };

  units = lib.attrNames unitSeconds;

  parse =
    s:
    let
      width = builtins.stringLength s;
      unit = builtins.substring (width - 1) 1 s;
      magnitude = toIntOrNull (builtins.substring 0 (width - 1) s);
    in
    if width < 2 || !(unitSeconds ? ${unit}) || magnitude == null || magnitude < 0 then
      null
    else
      {
        value = magnitude;
        inherit unit;
        seconds = magnitude * unitSeconds.${unit};
      };

  isDuration = s: builtins.isString s && parse s != null;

  describe = ''a whole number of ${lib.concatStringsSep "/" units} (for example "30s", "5m", "1h")'';

in
{
  inherit parse isDuration unitSeconds;

  toSeconds =
    context: s:
    let
      parsed = parse s;
    in
    if parsed == null then
      throw "${context}: '${toString s}' is not a duration. Expected ${describe}."
    else
      parsed.seconds;

  type = lib.types.addCheck lib.types.str isDuration // {
    name = "duration";
    description = "duration string: ${describe}";
  };
}
