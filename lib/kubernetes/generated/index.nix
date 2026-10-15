# The generated Kubernetes types, and the lookups over them.
#
# Hand-written, unlike what it loads. `cata-build generate` used to emit this
# file too, for one reason: `loadCrds` was an enumeration of the CRD group
# files it had just written. Those live beside the floes that install the CRDs
# now and arrive as an argument, so nothing here depends on what was
# generated — and a file that needs no regenerating is one fewer thing a
# refresh can leave stale.
#
# Of the three lookups, `coreKinds` answers "is this kind built in" and
# `typesByKind` takes every CRD group at once. `typesByKindForGroups` takes the
# Kubernetes API plus named groups only: a built-in kind is global because
# every cluster runs an apiserver, but a CRD kind exists only where something
# installed its CRD, so passing the groups one cluster establishes is what
# keeps another cluster's kinds out of scope. It skips groups it has no types
# for and leaves refusing them to the caller, which is the only side that can
# name the bundle at fault.
{ lib }:

let
  k8sVersions = {
    "1_31" = import ./k8s/1_31.nix { inherit lib; };
  };

  constructors = import ../constructors.nix { inherit lib; };

  # crdTypes :: { "<api group>" -> path }
  #
  # `floes/crds.nix` builds it by walking the floe tree, so a group's key, its
  # filename and the `apiVersion` prefix a floe writes are one string with no
  # mapping between them. It arrives as an argument because the types live
  # beside the floes that install the CRDs, and `lib/` is what the floes depend
  # on rather than the other way round.
  loadCrds =
    crdTypes: versioned:
    let
      k8sTypes = versioned // constructors;
    in
    lib.mapAttrs (_: path: import path { inherit lib k8sTypes; }) crdTypes;

  reservedAttrs = [
    "version"
    "mkTypedSubmodule"
    "mkResource"
    "crds"
  ];

  # The Kubernetes API at one release, with no CRDs in it. That is the whole
  # of what `coreKinds` needs, which is why `lib/lower/cluster.nix` can read it
  # without the floe tree in scope.
  forVersion =
    version:
    let
      safeVersion = builtins.replaceStrings [ "." ] [ "_" ] version;
    in
    k8sVersions.${safeVersion} or (throw "Unknown K8s version: ${version}");

  # And with them, for conformance. Separate so that nothing gets CRD types by
  # accident: a lookup table silently missing a group would resolve a custom
  # resource to nothing and check none of its fields.
  withCrds = crdTypes: versionedTypes: versionedTypes // { crds = loadCrds crdTypes versionedTypes; };

  flattenTypes =
    versionedTypes:
    let
      inherit (builtins)
        isAttrs
        attrNames
        foldl'
        elem
        ;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      flattenGroup =
        group:
        let
          apiVersions = builtins.sort (a: b: a < b) (attrNames group);
        in
        foldl' (acc: av: acc // group.${av}) { } apiVersions;
      k8sFlat = foldl' (acc: gn: acc // flattenGroup groups.${gn}) { } (attrNames groups);
      crdFlat =
        if versionedTypes ? crds then
          foldl' (acc: cn: acc // versionedTypes.crds.${cn}) { } (attrNames versionedTypes.crds)
        else
          { };
    in
    k8sFlat // crdFlat;

  typesByKind =
    versionedTypes:
    let
      inherit (builtins)
        isAttrs
        attrNames
        foldl'
        elem
        ;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addKinds =
        acc: kinds: foldl' (a: k: a // { ${k} = (a.${k} or [ ]) ++ [ kinds.${k} ]; }) acc (attrNames kinds);
      addGroup = acc: group: foldl' (a: av: addKinds a group.${av}) acc (attrNames group);
      k8sByKind = foldl' (acc: gn: addGroup acc groups.${gn}) { } (attrNames groups);
    in
    if versionedTypes ? crds then
      foldl' (acc: cn: addKinds acc versionedTypes.crds.${cn}) k8sByKind (attrNames versionedTypes.crds)
    else
      k8sByKind;

  crdGroups =
    versionedTypes: if versionedTypes ? crds then builtins.attrNames versionedTypes.crds else [ ];

  typesByKindForGroups =
    versionedTypes: groups:
    let
      inherit (builtins)
        isAttrs
        attrNames
        foldl'
        elem
        filter
        ;
      inherit (lib) filterAttrs;
      k8sGroups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addKinds =
        acc: kinds: foldl' (a: k: a // { ${k} = (a.${k} or [ ]) ++ [ kinds.${k} ]; }) acc (attrNames kinds);
      addGroup = acc: group: foldl' (a: av: addKinds a group.${av}) acc (attrNames group);
      k8sByKind = foldl' (acc: gn: addGroup acc k8sGroups.${gn}) { } (attrNames k8sGroups);
      known = filter (g: (versionedTypes.crds or { }) ? ${g}) groups;
    in
    foldl' (acc: g: addKinds acc versionedTypes.crds.${g}) k8sByKind known;

  coreKinds =
    versionedTypes:
    let
      inherit (builtins)
        isAttrs
        attrNames
        foldl'
        elem
        ;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addGroup =
        acc: group:
        foldl' (a: av: a // lib.genAttrs (attrNames group.${av}) (_: true)) acc (attrNames group);
    in
    foldl' (acc: gn: addGroup acc groups.${gn}) { } (attrNames groups);

  apiVersionOfType = type: (type.getSubOptions [ ]).apiVersion.default or null;

  apiVersionsForKind = byKind: kind: map apiVersionOfType (byKind.${kind} or [ ]);

  resolveResourceType =
    byKind: apiVersion: kind:
    let
      matching = builtins.filter (t: apiVersionOfType t == apiVersion) (byKind.${kind} or [ ]);
    in
    if matching == [ ] then null else builtins.head matching;

in
{
  inherit
    k8sVersions
    loadCrds
    forVersion
    withCrds
    flattenTypes
    ;
  inherit
    typesByKind
    apiVersionsForKind
    resolveResourceType
    coreKinds
    ;
  inherit crdGroups typesByKindForGroups;

}
