# What a cluster-component floe contributes, and the monoid that joins two of
# them. One kind, so every component floe has the same output type and the
# cluster picture is a fold rather than a pile.
{ lib, floe }:

let
  T = floe.T;

  # Store paths, not derivations. A kind schema must hold pure data: the
  # linker's scan walks every output recursively, `nix eval --json` has to
  # serialise it, and a derivation is a self-referential attrset that defeats
  # both. `"${drv}"` keeps the string context, so a build command
  # interpolating it still gets a real dependency.
  helmChartSchema = T.record {
    chart = T.str;
    releaseName = T.str;
    namespace = T.k8sName;
    values = T.attrsOf T.any;
  };

  imageSchema = T.record {
    registry = T.str;
    repository = T.str;
    tag = T.nullOr T.str;
    digest = T.nullOr T.str;
  };

  # RFC 0002 §6's shape, not `modules/lab/ops/types.nix`'s. The shipped type
  # carries `package = types.package`, a derivation, which cannot live in a
  # kind schema. Lowering a command to a wrapper script is the backend's job.
  opsCommandSchema = T.record {
    description = T.str;
    command = T.listOf T.str;
  };

  lintCheckSchema = T.record {
    description = T.str;
    severity = T.enum [
      "error"
      "warning"
    ];
    scope = T.enum [
      "per-file"
      "per-cluster"
    ];
    format = T.enum [
      "exit-code"
      "json"
    ];
    command = T.str;
  };

  verifyCheckSchema = T.record {
    description = T.str;
    timeout = T.str;
    expect = T.nullOr T.any;
    reject = T.listOf T.any;
  };

  ownerSchema = T.record {
    bootstrap = T.nullOr (
      T.enum [
        "install-target"
        "argocd"
      ]
    );
    steady = T.nullOr (
      T.enum [
        "imperative"
        "argocd"
      ]
    );
  };

  # There is no bundle-level `namespace`. A floe wrapping several charts emits
  # several bundles, and one bundle may install into several namespaces at
  # once — namespace is a property of each resource and each chart. This is
  # also exactly what `lib/eval/manifest-autoedges.nix` reads, so the derived
  # namespace edges come free.
  bundleSchema = T.record {
    # install — RFC 0002 §3's three shapes
    resources = T.attrsOf T.any;
    helmCharts = T.attrsOf helmChartSchema;
    yamls = T.listOf T.str;

    createNamespaces = T.listOf T.str;

    # `group/Kind` pairs this bundle installs the CRDs for. `crdProviders` in
    # manifest-autoedges reads CRDs out of `resources`; a bundle whose CRDs
    # arrive as an upstream YAML file has none to read, so it says so here.
    # RFC 0002 §7's `<bundle>.crd "<group>/<Kind>"`, as data.
    crds = T.listOf T.str;

    # readiness — RFC 0002 §4. Free-form because the fields a probe needs
    # depend on its `kind`; `lib/util/wait.nix:requiredBy` is the table that
    # says which, and the elaborator checks against it.
    ready = T.nullOr (T.attrsOf T.any);
    awaitRollout = T.bool;

    # ordering — RFC 0002 §5. Sibling bundle names in THIS floe's namespace
    # and nowhere else. Ordering between floes is not expressible here and
    # must not be: it comes from the link graph.
    needs = T.listOf T.str;

    owner = ownerSchema;

    images = T.attrsOf imageSchema;

    # operator surface — RFC 0002 §6, on the bundle because that is where the
    # locality is: a command can interpolate the namespace and the workload
    # names of the thing it is about.
    ops = T.attrsOf (T.attrsOf opsCommandSchema);
    lint = T.attrsOf lintCheckSchema;
    verify = T.attrsOf verifyCheckSchema;
  };

  componentSchema = T.record {
    bundles = T.attrsOf bundleSchema;

    # provide-instance name -> which of this floe's bundles must be ready
    # before a consumer of that provide may proceed. RFC 0002 §7's
    # `backedBy`, carried here rather than on the provide because a provide
    # is sealed against its signature and an extra field would be dropped.
    backs = T.attrsOf (T.listOf T.str);
  };

  # A verify `reject` key is a JMESPath, and the two halves have to be
  # parenthesised — `|` binds looser than `&&`, so the unparenthesised form
  # parses as a pipeline and evaluates to nonsense instead of erroring. There
  # is one correct spelling and it already exists; re-exported so a floe
  # author reaches it through `kinds` rather than writing it out.
  verifyTypes = import ../verify-types.nix { inherit lib; };

in
rec {
  component = floe.mkOutputKind {
    name = "catallaxy.component";
    schema = componentSchema;
  };

  inherit (verifyTypes) conditionIsNot fieldIsNot;

  # ---- constructors ------------------------------------------------------
  #
  # `T.record` demands every declared field, which is what makes sealing
  # total. These fill the ones a bundle usually has nothing to say about.

  mkBundle =
    {
      resources ? { },
      helmCharts ? { },
      yamls ? [ ],
      createNamespaces ? [ ],
      crds ? [ ],
      ready ? null,
      awaitRollout ? true,
      needs ? [ ],
      # Null means "whatever this cluster's default is". Resolving it needs a
      # fact the cluster holds and the bundle does not, so the elaborator
      # takes it as a parameter the way `lab.cd.defaultOwner` supplies it now.
      owner ? {
        bootstrap = null;
        steady = null;
      },
      images ? { },
      ops ? { },
      lint ? { },
      verify ? { },
    }:
    {
      inherit
        resources
        helmCharts
        yamls
        createNamespaces
        crds
        ready
        awaitRollout
        needs
        owner
        images
        ops
        lint
        verify
        ;
    };

  mkHelmChart =
    {
      chart,
      releaseName,
      namespace,
      values ? { },
    }:
    {
      chart = "${chart}";
      inherit releaseName namespace values;
    };

  mkComponent =
    {
      bundles ? { },
      backs ? { },
    }:
    {
      inherit bundles backs;
    };

  # ---- the monoid --------------------------------------------------------

  empty = {
    bundles = { };
    backs = { };
  };

  # Qualify a unit's component before joining: every bundle key becomes
  # `<unit>/<bundle>`, and `needs`, which names siblings in the floe's own
  # namespace, is resolved into the same space.
  #
  # This is what makes the join total. Two floes cannot produce the same key,
  # so `//` is disjoint union — associative, with `empty` as a two-sided
  # identity, and commutative on disjoint domains. `old-floe`'s `fold.nix` can
  # state none of those about itself, because it returns an unrealised
  # `mkMerge` and delegates the join to the module system.
  qualify =
    unit: c:
    let
      key = n: "${unit}/${n}";
    in
    {
      bundles = lib.mapAttrs' (
        n: b:
        lib.nameValuePair (key n) (
          b
          // {
            declaredBy = unit;
            needs = map key b.needs;
          }
        )
      ) c.bundles;

      # Keyed by provide instance, which is only unique within a unit, so the
      # key is qualified too. The elaborator looks one up as
      # `backs."${providerUnit}/${instance}"`.
      backs = lib.mapAttrs' (n: bs: lib.nameValuePair (key n) (map key bs)) c.backs;
    };

  join = a: b: {
    bundles = a.bundles // b.bundles;
    backs = a.backs // b.backs;
  };

  joinAll = lib.foldl' join empty;
}
