{ lib }:

let
  k8sVersions = {
    "1_31" = import ./k8s/1_31.nix { inherit lib; };
  };

  constructors = import ../constructors.nix { inherit lib; };

  loadCrds =
    versioned:
    let
      k8sTypes = versioned // constructors;
    in
    {
      "acme.cert-manager.io" = import ./crds/acme.cert-manager.io.nix { inherit lib k8sTypes; };
      "apiextensions.crossplane.io" = import ./crds/apiextensions.crossplane.io.nix {
        inherit lib k8sTypes;
      };
      "cert-manager.io" = import ./crds/cert-manager.io.nix { inherit lib k8sTypes; };
      "external-secrets.io" = import ./crds/external-secrets.io.nix { inherit lib k8sTypes; };
      "externaldns.k8s.io" = import ./crds/externaldns.k8s.io.nix { inherit lib k8sTypes; };
      "gateway.networking.k8s.io" = import ./crds/gateway.networking.k8s.io.nix { inherit lib k8sTypes; };
      "generators.external-secrets.io" = import ./crds/generators.external-secrets.io.nix {
        inherit lib k8sTypes;
      };
      "kaniop.rs" = import ./crds/kaniop.rs.nix { inherit lib k8sTypes; };
      "monitoring.coreos.com" = import ./crds/monitoring.coreos.com.nix { inherit lib k8sTypes; };
      "netbird.io" = import ./crds/netbird.io.nix { inherit lib k8sTypes; };
      "pkg.crossplane.io" = import ./crds/pkg.crossplane.io.nix { inherit lib k8sTypes; };
      "postgresql.cnpg.io" = import ./crds/postgresql.cnpg.io.nix { inherit lib k8sTypes; };
      "redis.redis.opstreelabs.in" = import ./crds/redis.redis.opstreelabs.in.nix {
        inherit lib k8sTypes;
      };
      "secrets.crossplane.io" = import ./crds/secrets.crossplane.io.nix { inherit lib k8sTypes; };
      "trust.cert-manager.io" = import ./crds/trust.cert-manager.io.nix { inherit lib k8sTypes; };
      "velero.io" = import ./crds/velero.io.nix { inherit lib k8sTypes; };
    };

  reservedAttrs = [
    "version"
    "mkTypedSubmodule"
    "mkResource"
    "crds"
  ];

  forVersion =
    version:
    let
      safeVersion = builtins.replaceStrings [ "." ] [ "_" ] version;
      k8sTypes = k8sVersions.${safeVersion} or (throw "Unknown K8s version: ${version}");
    in
    k8sTypes
    // {
      crds = loadCrds k8sTypes;
    };

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
    flattenTypes
    ;
  inherit
    typesByKind
    apiVersionsForKind
    resolveResourceType
    coreKinds
    ;
  inherit crdGroups typesByKindForGroups;

  default = forVersion "1.31";
}
