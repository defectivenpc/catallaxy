{ lib, floeCore }:

let
  core = floeCore;

  boolishStrings = [
    "true"
    "false"
    "True"
    "False"
    "TRUE"
    "FALSE"
    "yes"
    "no"
    "on"
    "off"
  ];

  isToggle = name: name == "enabled" || lib.hasSuffix "Enabled" name;

  noQuotedToggles =
    path: v:
    let
      at = if path == [ ] then "<values>" else lib.concatStringsSep "." path;
      leaf = if path == [ ] then "" else lib.last path;
      recurse =
        if builtins.isAttrs v && !(lib.isDerivation v) then
          lib.all (n: noQuotedToggles (path ++ [ n ]) v.${n}) (builtins.attrNames v)
        else if builtins.isList v then
          lib.all (i: noQuotedToggles (path ++ [ (toString i) ]) (builtins.elemAt v i)) (
            lib.range 0 (builtins.length v - 1)
          )
        else
          true;
    in
    if builtins.isString v && isToggle leaf && builtins.elem v boolishStrings then
      throw ''
        Helm value '${at}' is the string "${v}", not a boolean.

        A Go template reads every non-empty string as true, so this switches
        the setting on whatever it says. The chart renders either way, and no
        check downstream can tell the difference: the value exists and it has
        an effect — the opposite one.

        Write ${
          if
            builtins.elem v [
              "true"
              "True"
              "TRUE"
              "yes"
              "on"
            ]
          then
            "`true`"
          else
            "`false`"
        } without quotes.
      ''
    else
      recurse;

  T = core.T // {
    k8sName = {
      tag = "k8sName";
      name = "kubernetes name (DNS-1123 label)";
      check =
        v:
        builtins.isString v
        && builtins.stringLength v <= 63
        && builtins.match "[a-z0-9]([-a-z0-9]*[a-z0-9])?" v != null;
    };

    helmValues = {
      tag = "helmValues";
      name = "Helm values";
      check = noQuotedToggles [ ];
    };
  };
  mkSig =
    args: core.mkSig (removeAttrs args [ "behaviour" ]) // { behaviour = args.behaviour or [ ]; };
in
core
// {
  inherit T mkSig;
}
