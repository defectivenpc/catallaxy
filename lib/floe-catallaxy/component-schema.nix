# The schemas a cluster component is typed against.
{ lib, floe }:

let
  T = floe.T;

  stepType = import ../eval/step-type.nix { inherit lib; };

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

  # An image, from the ref an operator would type.
  #
  # Every one of the 49 declarations in the tree wrote the four fields out by
  # hand and 48 of them ended `digest = null;`. The grammar here is the
  # inverse of what `nix/checks/floe-gates.nix` builds to compare against
  # scraped YAML — `"${registry}/${repository}:${tag}"` plus `"@${digest}"` —
  # so declaration and comparison are now one spelling instead of two.
  #
  # The registry is required rather than inferred. `docker.io/traefik` and
  # `traefik` are the same image and the gate normalises them away at compare
  # time; refusing the second here makes the ambiguity unrepresentable at the
  imageSchema = T.record {
    registry = T.str;
    repository = T.str;
    tag = T.nullOr T.str;
    digest = T.nullOr T.str;
  };

  # A flag the generated CLI parses, as `--<name> <value>` or, for a bool,
  # `--<name>`. `values` is meaningful only for `enum` and is checked at
  # dispatch, so a wrong `--cluster` fails before the command runs rather than
  # by whatever the underlying tool makes of an unknown context.
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

  # RFC 0002 §6's shape. An earlier design carried
  # `package = types.package`, a derivation, which cannot live in a kind
  # schema — the linker's scan walks every output and `nix eval --json` has to
  # serialise it. So `package` is a store path *string*, the same
  # `"${drv}/bin/x"` trick `helmChartSchema.chart` already uses: it keeps the
  # string context, so the tool that interpolates it still gets a real
  # dependency.
  #
  # `command` and `package` are the two ways to say what runs, and exactly one
  # must be set. `command` is a fixed argv for the commands that are one line;
  # `package` is for the ones that need a script, which is most of them once
  # options and args are in play.
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

    # ---- Secrets, as `<namespace>/<name>` -------------------------------
    #
    # `lib/eval/secret-refs.nix` reads both sides off `resources`, so a floe
    # whose Secrets are ordinary manifests declares nothing. These three are
    # for what eval cannot see, and they exist for the same reason `crds`
    # does: a chart's output is opaque until apply.

    # Secrets this bundle causes to exist. A chart template, or a controller
    # this bundle installs that mints one.
    #
    # `*/<name>` means every namespace the cluster creates, which is what a
    # trust-manager Bundle with an empty `namespaceSelector` actually does.
    # The cluster expands it, because the set of namespaces is a fact the
    # cluster holds and the floe does not.
    secrets = T.listOf T.str;

    # Secrets this bundle reads somewhere the walk cannot follow — almost
    # always a Helm value. Harbor is the case: four credentials reach it as
    # chart values, so nothing in its rendered resources names them.
    needsSecrets = T.listOf T.str;

    # Objects that arrive from outside the manifest stream: a plan step, an
    # operator, a human. Secrets mostly, and ConfigMaps too — trust-manager's
    # CA bundle is written into every namespace by a controller, and the lint
    # checks both kinds against the same list. The name has stayed
    # `externalSecrets` because that is what every caller declares; what it
    # lowers to, `runtimeMaterialised`, has always been kind-neutral.
    #
    # These satisfy the cluster's coherence check the same way `secrets` does,
    # and are additionally reported to `cata lab lint` as `runtimeMaterialised`
    # so its dangling-reference rule agrees with ours.
    #
    # The distinction from `secrets` is who to talk to when it is missing, and
    # that is worth keeping separate: one is a bug in this repo, the other is
    # a lab that was not set up.
    externalSecrets = T.listOf T.str;

    # Hostnames this bundle causes to be routed by something it installs,
    # rather than by an HTTPRoute in its own manifests.
    #
    # The elaborator reads routes off `resources` to build `exposedHosts`,
    # which is what the lab's ingress builds its host map from. An operator
    # that renders the route instead — kaniop does, from `Kanidm.spec.gateway`
    # — leaves nothing for that walk to find, so the host is unreachable from
    # outside the cluster and unroutable inside it.
    #
    # Same shape of gap as `externalSecrets`, and here for the same reason: a
    # chart or a controller's output is opaque until apply, so the floe says
    # what it knows.
    routedHosts = T.listOf T.str;

    # readiness — RFC 0002 §4. Free-form because the fields a probe needs
    # depend on its `kind`; `lib/kubernetes/wait.nix:requiredBy` is the table that
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

  # Drift a CD tool should not fight. `reason` is required and deliberately
  # has no default: a rule with no rationale cannot be retired safely and is
  # indistinguishable from one added to turn a red light green.
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

    # provide-instance name -> which of this floe's bundles must be ready
    # before a consumer of that provide may proceed. RFC 0002 §7's
    # `backedBy`, carried here rather than on the provide because a provide
    # is sealed against its signature and an extra field would be dropped.
    backs = T.attrsOf (T.listOf T.str);

    # A floe claiming its image set is exhaustive, so the cluster can check
    # that claim against what it actually rendered. Floe-level rather than
    # per-bundle: it is a statement about the floe's whole output.
    imagesComplete = T.bool;

    # Folded to the cluster with the floe's name prefixed, so a failure names
    # the floe that objected rather than landing in one flat list.
    assertions = T.listOf assertionSchema;
    warnings = T.listOf T.str;

    drift = T.listOf driftSchema;

    # Plan steps this floe contributes: work that is neither applying a
    # manifest nor provisioning a cluster. A teardown that has to drain
    # records before the cluster goes, a CNI that must land before any node is
    # Ready, a handover to a CD tool.
    #
    # The same module type the lab uses for its own `lab.steps`, so there is
    # one spelling of what a step is. This was `attrsOf any`, normalised at the
    # lab, on the belief that a kind schema could not hold a module type — but
    # that rule is about values, and a schema is never serialised. The cost of
    # the belief was that a malformed step named the lab rather than the floe
    # that wrote it.
    steps = T.attrsOf (T.moduleType stepType.declaredStepType);
  };

  # A verify `reject` key is a JMESPath, and the two halves have to be
  # parenthesised — `|` binds looser than `&&`, so the unparenthesised form
  # parses as a pipeline and evaluates to nonsense instead of erroring. There
  # is one correct spelling and it already exists; re-exported so a floe
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
