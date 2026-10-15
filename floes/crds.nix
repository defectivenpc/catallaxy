# Which floes have typed CRDs, and the types themselves.
#
# Derived, not listed. A floe carrying a `crds.nix` is a floe whose CRDs get
# Nix types, and `crds/<group>.nix` beside it is the output — so adding one
# needs no central edit and deleting a floe deletes its types with it.
#
# It was `nix/crd-types.nix`: eleven chart names written out to say "every
# chart that ships CRDs, except argocd and cilium", kept in step with
# `lib/charts.nix` by a `throw`. Those two are absent here for the same reason
# they were absent there — nothing renders their CRDs, so group-scoped
# resolution would never bring the types into scope — but now they are absent
# by *not carrying a file* rather than by being left off a list.
#
# Two readers, which is why this is one expression. `sources` is what the
# generator reads; `types` is what conformance resolves against. A group
# appearing in one and not the other means the committed types are stale, which
# is what `generated-types` compares.
{ lib }:

let
  # A component floe is a directory and a lab floe is a file, so `floes/` holds
  # both shapes. Only a directory can carry a `crds.nix` beside it.
  dirOfFloe = path: if builtins.pathExists (path + "/default.nix") then path else dirOf path;

  floeDirs = lib.mapAttrs (_: dirOfFloe) (
    lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ./.))
  );

  withCrds = lib.filterAttrs (_: dir: builtins.pathExists (dir + "/crds.nix")) floeDirs;

  groupsIn =
    dir:
    let
      crdDir = dir + "/crds";
    in
    lib.optionals (builtins.pathExists crdDir) (
      map (f: {
        group = lib.removeSuffix ".nix" f;
        path = crdDir + "/${f}";
      }) (lib.attrNames (lib.filterAttrs (_: k: k == "regular") (builtins.readDir crdDir)))
    );
in
{
  # floe name -> the function yielding its CRD artifact, for `cata-build
  # generate`. Called with whatever the artifact needs: a chart table, an API
  # spec set, or both.
  sources = lib.mapAttrs (_: dir: import (dir + "/crds.nix")) withCrds;

  # API group -> the generated type file. Keyed by the group verbatim, which is
  # also the filename and also the `apiVersion` prefix a floe writes — one
  # string, no mapping between the three.
  #
  # A group defined in two floes would be two files claiming one key;
  # `cata-build generate` refuses that at the source, so this merge is disjoint
  # by construction.
  types = lib.listToAttrs (
    lib.concatMap (dir: map (g: lib.nameValuePair g.group g.path) (groupsIn dir)) (
      lib.attrValues withCrds
    )
  );
}
