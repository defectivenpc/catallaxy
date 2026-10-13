# One name per signature, across the whole floe set.
#
# A hole's name is the first thing a reader sees, and before this it did not
# identify what the hole was for. `provides.operator` bound four different
# signatures — `POSTGRES_OPERATOR`, `IDENTITY_OPERATOR`, `REDIS_OPERATOR`,
# `MESH_OPERATOR` — so reading it told you nothing. `GATEWAY_API` was `api` on
# its provider and `gatewayApi` on both its consumers, and `TRUST_BUNDLE` was
# `distribution` on one side and `trust` on the other, so following a promise
# to whoever satisfied it meant knowing both names.
#
# The signature's `as` is now the one name, and this holds the line. Cheap:
# pure Nix over the floe definitions, no lab evaluated, and it fires the
# instant someone binds a signature under a new name rather than when a reader
# eventually notices.
#
# Over the *flattened* set, which `floe-gates.nix` is not — it takes
# `(import ../../floes).components` and so has never looked at `floes/lab/`,
# `floes/clusters/` or `floes/provisioners/` at all.
{
  lib,
  pkgs,
  cataCharts,
  k8sSpecs,
  catallaxy,
  floeSet,
}:

let
  inherit (catallaxy) floe sigs kinds;

  defOf =
    name:
    import floeSet.${name} {
      inherit
        lib
        pkgs
        catallaxy
        cataCharts
        k8sSpecs
        floes
        ;
      inherit
        floe
        sigs
        kinds
        ;
    };

  # A floe whose units are other floes reaches them through this, built the
  # way `lib/lab.nix` builds it and lazy for the same reason.
  floes = lib.mapAttrs (
    name: _:
    let
      def = defOf name;
    in
    def // { __functor = _: def.instantiate; }
  ) floeSet;

  # A floe may bind one signature twice under different names
  # §175-180 contemplates exactly that for two instances of one thing. No
  # shipped floe does, so this starts empty; its existence is what documents
  # the escape hatch, and adding an entry is a deliberate act rather than a
  # silent drift.
  renamed = { };

  holesOf =
    name:
    let
      def = defOf name;
      each =
        kind: holes:
        lib.mapAttrsToList (hole: sig: {
          inherit
            name
            kind
            hole
            ;
          inherit (sig) canonicalName;
          sigName = sig.name;
        }) holes;
    in
    each "requires" def.requires ++ each "optional" def.optional ++ each "provides" def.provides;

  all = lib.concatMap holesOf (lib.attrNames floeSet);

  wrong = lib.filter (h: h.hole != h.canonicalName && !(renamed.${h.name} or { }) ? ${h.hole}) all;

  findings = map (
    h: "${h.name}: ${h.kind}.${h.hole} binds ${h.sigName}, whose canonical name is '${h.canonicalName}'"
  ) wrong;
in
{
  floe-names = pkgs.runCommand "floe-names-tests" { } ''
    ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
    ${lib.optionalString (findings != [ ]) ''
      echo "" >&2
      echo "A hole's name is the first thing a reader sees, and it has to say" >&2
      echo "which signature it is. Rename it to the signature's \`as\`, or — if" >&2
      echo "this floe genuinely binds one signature twice — add it to \`renamed\`" >&2
      echo "in nix/checks/floe-names.nix, which is there to be used deliberately." >&2
      exit 1
    ''}
    touch $out
  '';
}
