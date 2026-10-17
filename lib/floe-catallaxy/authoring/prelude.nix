# The type prelude this distribution speaks: core's, plus the types its domain
# has.
{ lib, floeCore }:

let
  core = floeCore;

  # Strings a Go template reads as true. Every non-empty string is truthy, so
  # a quoted `"false"` turns a setting *on* — and `helm template` renders it
  # without complaint, because the value exists and has an effect. It just has
  # the opposite one.
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

  # Only a key named like a toggle, which is the scope the evidence supports.
  #
  # A string-typed boolean is ordinary elsewhere: velero's
  # `backupStorageLocation[].config` is handed to a CR field that is
  # `map[string]string`, so `s3ForcePathStyle = "true"` is correct there and
  # the floe's suite asserts it. An unscoped rule flagged it on its first run.
  # Numbers stay out for the same reason — cilium's schema types
  # `k8sServicePort` as `["string","integer"]` and `"6443"` is deliberate.
  #
  # So this is narrower than "a boolean is never a string": a key called
  # `enabled` is a switch, and a switch is never a string. Of the chart values
  # the shipped floes write, that holds for every one.
  isToggle = name: name == "enabled" || lib.hasSuffix "Enabled" name;

  # Throws rather than returning false: `check` is a predicate, so returning
  # false reports "expected Helm values, got {...}" and names neither the key
  # nor the value. The path is the whole message here.
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

    /*
      A chart's values, which are only as typed as the chart makes them.

      Nothing here knows what settings a chart has — `nix/checks/chart-values.nix`
      answers that by rendering, and Helm answers the types for the nine of
      twenty-one charts that ship a `values.schema.json`. What this catches is
      the one error neither can: a *toggle* written as a string, which exists,
      renders, and switches the setting the other way.
    */
    helmValues = {
      tag = "helmValues";
      name = "Helm values";
      check = noQuotedToggles [ ];
    };
  };
  # `mkSig`, plus one argument this domain has and core does not.
  #
  # `behaviour` names the runtime checks any provider of a signature owes.
  # Compatibility settles a provider's *shape*; nothing settles that what
  # answers `X509_ISSUANCE` actually signs anything, and that gap is NixOS
  # RFC 0189's `behaviorTest` — which the library briefly carried as an opaque
  # field it could not run, and deleted.
  #
  # It belongs here rather than there, and the reason is the whole design: the
  # checks already exist. A floe declares `verify.<name>` in its component,
  # `cata lab verify` runs them, and `cata-e2e` runs that against a real
  # cluster. So a signature does not carry a *test* — it carries the
  # obligation that a provider have one, by name, discharged by a check the
  # provider already writes. Core stays out: `verify` is this distribution's
  # concept, run by this distribution's CLI, and a word for it in core would
  # be vocabulary for a mechanism only one distribution has.
  #
  # Core's `mkSig` has a closed argument pattern, so this strips the argument
  # before calling it and puts it back on the result. No library change, and a
  # signature is still exactly what core thinks it is.
  mkSig =
    args: core.mkSig (removeAttrs args [ "behaviour" ]) // { behaviour = args.behaviour or [ ]; };
in
core
// {
  inherit T mkSig;
}
