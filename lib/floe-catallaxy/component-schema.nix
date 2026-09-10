# The schemas a cluster component is typed against.
{ lib, floe }:

let
  T = floe.T;

  stepType = import ../eval/step-type.nix { inherit lib; };

  helmChartSchema = T.record {
    chart = T.str;
    releaseName = T.str;
    namespace = T.k8sName;
    values = T.attrsOf T.any;

    # `<hook name> -> what does the job instead`. Install order here comes
    # from the wave graph, so a chart's lifecycle hooks are dropped; saying so
    # is what keeps the drop a decision rather than an accident. Keyed by name
    # because a hook is a Job and its RBAC sharing one. Test hooks are dropped
    # without asking; `lib/render/manifest.nix` refuses any other undeclared
    # one.
    replacedHooks = T.attrsOf T.str;
  };

  imageSchema = T.record {
    registry = T.str;
    repository = T.str;
    tag = T.nullOr T.str;
    digest = T.nullOr T.str;
  };

  opsOptionSchema = T.record {
    type = T.enum [
      "str"
      "bool"
      "enum"
    ];
    values = T.listOf T.str;
    required = T.bool;
    default = T.nullOr T.str;
    description = T.str;
  };

  # A positional. `variadic` is last-only and takes the rest, which is what
  # `velero backup create` wants for its passthrough flags.
  opsArgSchema = T.record {
    name = T.str;
    description = T.str;
    required = T.bool;
    variadic = T.bool;
  };

  opsCommandSchema = T.record {
    description = T.str;
    command = T.listOf T.str;
    package = T.nullOr T.str;
    options = T.attrsOf opsOptionSchema;
    args = T.listOf opsArgSchema;
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

  bundleSchema = T.record {
    # install — RFC 0002 §3's three shapes
    resources = T.attrsOf T.any;
    helmCharts = T.attrsOf helmChartSchema;
    yamls = T.listOf T.str;

    createNamespaces = T.listOf T.str;

    crds = T.listOf T.str;

    # ---- Secrets, as `<namespace>/<name>` -------------------------------

    secrets = T.listOf T.str;

    needsSecrets = T.listOf T.str;

    externalSecrets = T.listOf T.str;

    routedHosts = T.listOf T.str;

    ready = T.nullOr (T.attrsOf T.any);
    awaitRollout = T.bool;

    needs = T.listOf T.str;

    owner = ownerSchema;

    images = T.attrsOf imageSchema;

    ops = T.attrsOf (T.attrsOf opsCommandSchema);
    lint = T.attrsOf lintCheckSchema;
    verify = T.attrsOf verifyCheckSchema;
  };

  driftSchema = T.record {
    reason = T.str;
    group = T.str;
    kinds = T.listOf T.str;
    managedBy = T.listOf T.str;
  };

  assertionSchema = T.record {
    assertion = T.bool;
    message = T.str;
  };

  componentSchema = T.record {
    bundles = T.attrsOf bundleSchema;

    backs = T.attrsOf (T.listOf T.str);

    imagesComplete = T.bool;

    # Folded to the cluster with the floe's name prefixed, so a failure names
    # the floe that objected rather than landing in one flat list.
    assertions = T.listOf assertionSchema;
    warnings = T.listOf T.str;

    drift = T.listOf driftSchema;

    steps = T.attrsOf (T.moduleType stepType.declaredStepType);
  };

in
{
  inherit
    helmChartSchema
    imageSchema
    opsOptionSchema
    opsArgSchema
    opsCommandSchema
    lintCheckSchema
    verifyCheckSchema
    ownerSchema
    bundleSchema
    driftSchema
    assertionSchema
    componentSchema
    ;
}
