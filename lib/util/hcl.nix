{ lib }:

let
  escape = lib.escape [
    "\\"
    "\""
  ];

  value =
    v:
    if builtins.isString v then
      "\"${escape v}\""
    else if builtins.isBool v then
      lib.boolToString v
    else if builtins.isInt v || builtins.isFloat v then
      toString v
    else if builtins.isList v then
      "[${lib.concatMapStringsSep ", " value v}]"
    else
      throw "hcl: a ${builtins.typeOf v} has no HCL form; use a string, number, bool, list or attrset";

  body =
    indent: attrs:
    lib.concatStrings (
      lib.mapAttrsToList (
        k: v:
        if builtins.isAttrs v then
          "${indent}${k} {\n${body (indent + "  ") v}${indent}}\n"
        else
          "${indent}${k} = ${value v}\n"
      ) attrs
    );
in
{
  inherit value body;

  block =
    kind: label: attrs:
    "${kind} \"${escape label}\" {\n${body "  " attrs}}\n";
}
