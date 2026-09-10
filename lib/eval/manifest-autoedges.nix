# Ordering edges derived from what a resource structurally needs — its
# namespace, its CRD, the Secret it reads.
{ lib }:

let
  inherit (lib)
    attrNames
    attrValues
    filter
    foldl'
    mapAttrs
    unique
    ;

  resKind = r: r.kind or "";

  groupOf =
    apiVersion:
    let
      parts = lib.splitString "/" apiVersion;
    in
    if builtins.length parts < 2 then "" else builtins.head parts;

  resRef = r: "${groupOf (r.apiVersion or "")}/${resKind r}";
  resNs = r: r.metadata.namespace or null;
  resName = r: r.metadata.name or null;
  isNamespace = r: resKind r == "Namespace";
  isCRD = r: resKind r == "CustomResourceDefinition";

  isApplierConfig = r: groupOf (r.apiVersion or "") == "kapp.k14s.io";
  isSecretStore =
    r:
    builtins.elem (resKind r) [
      "SecretStore"
      "ClusterSecretStore"
    ];
  isExternalSecret = r: resKind r == "ExternalSecret";
  isPushSecret = r: resKind r == "PushSecret";

  resourcesOf = bundle: attrValues (bundle.resources or { });

  secretRefs = import ./secret-refs.nix { inherit lib; };

  secretsMadeBy =
    bundle:
    unique (
      lib.concatMap secretRefs.secretsCreatedBy (resourcesOf bundle)
      ++ (bundle.secrets or [ ])
      ++ (bundle.externalSecrets or [ ])
    );

  secretsReadBy =
    bundle:
    unique (
      lib.concatMap secretRefs.secretsUsedBy (resourcesOf bundle) ++ (bundle.needsSecrets or [ ])
    );

  indexBy =
    bundles: pick:
    foldl' (
      acc: bundleName:
      foldl' (inner: key: inner // { ${key} = bundleName; }) acc (pick bundles.${bundleName})
    ) { } (attrNames bundles);

  namespaceProviders =
    { bundles, namespaceAggregate }:
    let
      fromCreateNamespaces =
        if namespaceAggregate == null then
          { }
        else
          foldl' (
            acc: bundleName:
            foldl' (inner: ns: inner // { ${ns} = namespaceAggregate; }) acc (
              bundles.${bundleName}.createNamespaces or [ ]
            )
          ) { } (attrNames bundles);

      # A bundle declaring the Namespace object itself outranks the aggregate:
      # it is the thing that actually carries the labels and the finalizers.
      fromResources = indexBy bundles (
        b: filter (n: n != null) (map resName (filter isNamespace (resourcesOf b)))
      );
    in
    fromCreateNamespaces // fromResources;

  secretStoreProviders =
    bundles:
    indexBy bundles (b: filter (n: n != null) (map resName (filter isSecretStore (resourcesOf b))));

  crdProviders =
    bundles:
    indexBy bundles (
      b: map (r: "${r.spec.group or ""}/${r.spec.names.kind or ""}") (filter isCRD (resourcesOf b))
    );

  namesProvidedBy =
    providers: bundleName: prefix:
    map (key: "${prefix}:${key}") (filter (key: providers.${key} == bundleName) (attrNames providers));

  autoAfter =
    bundle:
    let
      resources = resourcesOf bundle;

      consumedNamespaces = unique (
        filter (n: n != null) (
          (map resNs resources)
          ++ (map (h: h.namespace or null) (attrValues (bundle.helmCharts or { })))
          ++ (bundle.createNamespaces or [ ])
        )
      );

      consumedStores = unique (
        filter (n: n != null) (
          map (r: r.spec.secretStoreRef.name or null) (filter isExternalSecret resources)
          ++ lib.concatMap (r: map (s: s.name or null) (r.spec.secretStoreRefs or [ ])) (
            filter isPushSecret resources
          )
        )
      );
    in
    map (n: "optional:namespace:${n}") consumedNamespaces
    ++ map (n: "optional:secretstore:${n}") consumedStores;

  autoRequires =
    coreKinds: bundle:
    let
      wanted = filter (r: !(coreKinds ? ${resKind r}) && !(isApplierConfig r)) (resourcesOf bundle);
    in
    unique (map (r: "kind:${resRef r}") wanted);

  deriveAutoEdges =
    {
      bundles,
      namespaceAggregate ? null,
      coreKinds ? { },
    }:
    let
      namespaces = namespaceProviders { inherit bundles namespaceAggregate; };
      stores = secretStoreProviders bundles;
      crds = crdProviders bundles;
      secrets = indexBy bundles secretsMadeBy;
    in
    mapAttrs (
      name: bundle:
      bundle
      // {
        provides = unique (
          (bundle.provides or [ ])
          ++ [ "bundle:${name}" ]
          ++ lib.optional (bundle.declaredBy != "cluster") "floe:${bundle.declaredBy}"
          ++ namesProvidedBy namespaces name "namespace"
          ++ namesProvidedBy stores name "secretstore"
          ++ namesProvidedBy secrets name "secret"
          ++ namesProvidedBy crds name "kind"
        );
        after = unique (
          (bundle.after or [ ])
          ++ (autoAfter bundle)

          # A bundle that both makes and reads a Secret is self-satisfied:
          # they apply together, and an edge to itself is a cycle.
          ++ map (s: "optional:secret:${s}") (lib.subtractLists (secretsMadeBy bundle) (secretsReadBy bundle))
        );
        requires = unique ((bundle.requires or [ ]) ++ (autoRequires coreKinds bundle));
      }
    ) bundles;

in
{
  inherit
    deriveAutoEdges
    namespaceProviders
    secretStoreProviders
    crdProviders
    autoAfter
    autoRequires
    secretsMadeBy
    secretsReadBy
    ;
}
