# Reading numbers out of strings, without a character class.
{ lib }:

{
  toIntOrNull =
    s:
    if !(builtins.isString s) then
      null
    else
      let
        read = builtins.tryEval (lib.toInt s);
      in
      if read.success then read.value else null;
}
