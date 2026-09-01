# What a cluster-component floe contributes, and the monoid that joins two of
# them. One kind, so every component floe has the same output type and the
# cluster picture is a fold rather than a pile.
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

  # RFC 0002 §6's shape. `modules/lab/ops/types.nix` carries
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

    # Secrets that arrive from outside the manifest stream: a plan step, an
    # operator, a human. These satisfy the cluster's coherence check the same
    # way `secrets` does, and are additionally reported to `cata lab lint` as
    # `runtimeMaterialised` so its dangling-reference rule agrees with ours.
    #
    # The distinction from `secrets` is who to talk to when it is missing, and
    # that is worth keeping separate: one is a bug in this repo, the other is
    # a lab that was not set up.
    externalSecrets = T.listOf T.str;

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

  # What a floe declares about its own network needs, from which the cluster
  # synthesises NetworkPolicies. `reaches` names `<unit>/<label>` — the unit
  # namespace the join already established, so a label no enabled floe serves
  # is an error rather than a rule that renders and does nothing.
  #
  # `declared` is not redundant with the rest being empty: a floe that needs
  # nothing beyond the namespace default still sets it, because otherwise it
  # is indistinguishable from one nobody has looked at, and telling those two
  # apart is the whole point of asking.
  portSchema = T.record {
    port = T.any;
    protocol = T.enum [
      "TCP"
      "UDP"
      "SCTP"
    ];
  };

  networkSchema = T.record {
    declared = T.bool;
    serves = T.attrsOf (
      T.record {
        port = T.any;
        protocol = T.enum [
          "TCP"
          "UDP"
          "SCTP"
        ];
        fromExternal = T.bool;
        fromApiServer = T.bool;
      }
    );
    reaches = T.listOf T.str;
    egress = T.record {
      internet = T.record { ports = T.listOf portSchema; };
      cidrs = T.listOf (
        T.record {
          cidr = T.str;
          except = T.listOf T.str;
          ports = T.listOf portSchema;
        }
      );
    };
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

    network = networkSchema;

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
      secrets ? [ ],
      needsSecrets ? [ ],
      externalSecrets ? [ ],
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
        secrets
        needsSecrets
        externalSecrets
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

  # An ops command. `command` and `package` are the two ways to say what runs
  # and exactly one must be set; the elaborator refuses a command with neither,
  # because the generated tool would match the branch and `exec` nothing.
  mkOpsCommand =
    {
      description,
      command ? [ ],
      package ? null,
      options ? { },
      args ? [ ],
    }:
    {
      inherit description command package;
      options = lib.mapAttrs (_: mkOpsOption) options;
      args = map mkOpsArg args;
    };

  # `values` is meaningful only for `enum`, and `default` only for `str` —
  # a bool's absence is its default and an enum with one would be a choice
  # nobody made.
  mkOpsOption =
    {
      type ? "str",
      values ? [ ],
      required ? false,
      default ? null,
      description ? "",
    }:
    {
      inherit
        type
        values
        required
        default
        description
        ;
    };

  mkOpsArg =
    {
      name,
      description ? "",
      required ? true,
      variadic ? false,
    }:
    {
      inherit
        name
        description
        required
        variadic
        ;
    };

  # ---- constructors a floe ships for its consumers ------------------------
  #
  # `mkGeneratedSecret` and `mkRoute` are the same idea, and it is the one
  # that replaced the fan-in: a floe that installs a capability ships the
  # constructor for using it, and the *consumer* emits the resource into its
  # own bundle.
  #
  # This is how Kubernetes already works. A registered CRD is a primitive
  # anyone may use; making the installing floe the only party that can render
  # one is a restriction the cluster does not have, and expressing it needed a
  # `requiresMany` whose ordering ran backwards for every case except routes.
  #
  # What the installing floe keeps is the part it is uniquely able to do:
  # knowing what a well-formed one looks like, and refusing a malformed one
  # at construction, where the trace names the floe that asked.

  # A route through the gateway. The consumer already holds the sealed
  # `API_GATEWAY` value, so it never spells the gateway's name, its namespace
  # or its listener — `parentRef` carries all three.
  mkRoute =
    {
      gateway,
      name,
      namespace,
      service,
      port,
      # Defaults to `<name>.<zone>`, which is what every consumer wanted and
      # each was computing for itself.
      hostname ? "${name}.${gateway.baseDomain}",
      path ? "/",
    }:
    let
      inZone = hostname == gateway.baseDomain || lib.hasSuffix ".${gateway.baseDomain}" hostname;
    in
    if !inZone then
      # A route naming a host outside the zone attaches happily and then
      # serves nothing: the wildcard certificate does not cover it, and no DNS
      # in the lab answers for it. This used to be an assertion on the
      # gateway, over the fan-in — which could only say *that* some route was
      # wrong. Here the eval trace names the floe that wrote it.
      throw ''
        route '${name}' asks for hostname '${hostname}', which is outside the
        gateway's zone '${gateway.baseDomain}'.

        The gateway cannot serve it: the wildcard certificate does not cover
        it and no DNS in the lab answers for it.
      ''
    else
      {
        apiVersion = "gateway.networking.k8s.io/v1";
        kind = "HTTPRoute";
        metadata = {
          inherit name namespace;
          labels."app.kubernetes.io/managed-by" = "catallaxy";
        };
        spec = {
          parentRefs = [ gateway.parentRef ];
          hostnames = [ hostname ];
          rules = [
            {
              matches = [
                {
                  path = {
                    type = "PathPrefix";
                    value = path;
                  };
                }
              ];
              backendRefs = [
                {
                  name = service;
                  inherit port;
                }
              ];
            }
          ];
        };
      };

  # An OAuth2 client, registered with whatever provides OIDC_PROVIDER.
  #
  # Returns both halves a consumer needs: the resource to put in its own
  # bundle, and the reference to read the credentials back out of. The
  # operator writes the Secret once it has reconciled the client, so the
  # consumer never sees the value at eval — which is what keeps a client
  # secret out of the rendered manifests.
  #
  # The Secret's name is the operator's convention and not a field: kaniop's
  # `KanidmOAuth2Client` has no `spec.secretName`, and a client carrying one
  # is rejected whole under server-side apply with
  # `field not declared in schema` — so setting it produced no client, no
  # Secret, and a consumer waiting forever on both.
  #
  # `<client>-kanidm-oauth2-credentials`, verified against kaniop 0.11.1 by
  # applying a client and reading back what appeared. The `kanidm` in the
  # middle is a literal rather than the instance's name: the Secret carries
  # `app.kubernetes.io/name: kanidm` alongside `instance: <client>`, so it is
  # the product and not the reference.
  #
  # Written here once, which is the whole mitigation available. A consumer
  # guessing it for itself would be N places to change; this is one, and it is
  # next to the resource whose operator decides it.
  mkOAuth2Client =
    {
      provider,
      name,
      namespace,
      # Where the app lives. The default redirect is the one nearly every
      # OIDC library uses; a consumer whose library differs says so.
      origin,
      redirectUrls ? [ "${origin}/oauth2/callback" ],
      displayName ? name,
      scopeMap ? [ ],
      # A public client is one that cannot keep a secret — a SPA or a CLI.
      # The operator writes no Secret for one, so there is nothing to read.
      public ? false,
    }:
    let
      secretName = "${name}-kanidm-oauth2-credentials";
    in
    if !provider.clientsAnyNamespace && namespace != provider.ref.namespace then
      # Admitted, stored, and never reconciled: the consumer waits on a Secret
      # that is not coming. Refused here, where the trace names the floe that
      # asked, rather than at whatever timeout notices later.
      throw ''
        OAuth2 client '${name}' is in namespace '${namespace}', and the OIDC
        provider only reconciles clients in its own ('${provider.ref.namespace}').

        Nothing would report this: the resource is admitted and then ignored,
        and the Secret it should produce never appears.
      ''
    else
      {
        resource = {
          apiVersion = "${lib.head (lib.splitString "/" provider.clientCrd)}/v1beta1";
          kind = lib.last (lib.splitString "/" provider.clientCrd);
          metadata = {
            inherit name namespace;
            labels."app.kubernetes.io/managed-by" = "catallaxy";
          };
          spec = {
            kanidmRef = provider.ref;
            displayname = displayName;
            inherit origin;
            redirectUrl = redirectUrls;
          }
          // lib.optionalAttrs public { public = true; }
          // lib.optionalAttrs (scopeMap != [ ]) { inherit scopeMap; };
        };

        # An OIDC client is its own issuer under kanidm: tokens for this
        # client carry `<issuer>/oauth2/openid/<client>` and its keys are
        # published beneath that. A consumer validating a token itself — as
        # netbird's management does, rather than delegating to a library that
        # reads a discovery document — needs both.
        #
        # kanidm's path scheme, like the Secret's name above, and here for the
        # same reason: one place, next to the resource whose server decides
        # it, rather than a string every consumer rebuilds.
        oidc = {
          clientId = name;
          issuer = "${provider.issuer}/oauth2/openid/${name}";
          jwksUri = "${provider.issuer}/oauth2/openid/${name}/public_key.jwk";
          discoveryUrl = "${provider.issuer}/oauth2/openid/${name}/.well-known/openid-configuration";
          inherit (provider) authorizationEndpoint tokenEndpoint;
        };

        # Canonical keys, always present on a confidential client. Null for a
        # public one, because the operator writes no Secret at all and a
        # reference to it would be a reference to nothing.
        secret =
          if public then
            null
          else
            {
              inherit namespace;
              name = secretName;
              idKey = "CLIENT_ID";
              secretKey = "CLIENT_SECRET";
            };
      };

  # A credential the floe mints for itself: an external-secrets `Password`
  # generator and the ExternalSecret that lands its output in a Secret.
  #
  # Returns `{ resources; secrets; ready; }` to merge into a bundle, so the
  # floe emits it in its own bundle rather than writing into a lab channel.
  # The floe must `require` SECRET_GENERATION — these two kinds are reconciled
  # by the external-secrets controller and its validating webhook rejects them
  # outright when it is not running.
  #
  # Every default here is an incident, not a preference.
  mkGeneratedSecret =
    {
      namespace,
      secret,
      key ? "password",
      length ? 24,
      digits ? null,
      # Zero, because a consumer that puts the value in a URL, a connection
      # string, or a config file it does not quote breaks on them.
      symbols ? 0,
      symbolCharacters ? null,
      allowRepeat ? true,
      noUpper ? false,
      # `base64` is for a consumer that decodes the value to get raw key bytes
      # rather than reading it as a string. Under it, `length` counts the bytes
      # the consumer decodes, not the characters that reach the Secret.
      encoding ? "plain",
      # Literals to place beside the generated value, for a consumer that will
      # not start without both keys. Grafana is the case: its chart reads
      # `admin-user` and `admin-password` from one Secret, and a username is
      # not a secret. Nothing here is encoded, whatever `encoding` says.
      extraData ? { },
    }:
    let
      generatorRef = {
        apiVersion = "generators.external-secrets.io/v1alpha1";
        kind = "Password";
        name = secret;
      };

      # A template names every key it writes, so it is the only way to put a
      # literal beside the generated value. `rewrite` below cannot: it renames
      # the generator's one output and has nowhere to put a second key.
      usesTemplate = encoding == "base64" || extraData != { };

      managed.labels."app.kubernetes.io/managed-by" = "catallaxy";
    in
    {
      # The ExternalSecret's target is readable off `resources`, so this is
      # belt and braces — but a floe reading its own generated credential
      # through a Helm value has no other way to be believed.
      secrets = [ "${namespace}/${secret}" ];

      resources = {
        "${secret}-generator" = {
          inherit (generatorRef) apiVersion kind;
          metadata = {
            name = secret;
            inherit namespace;
          }
          // managed;
          spec = {
            inherit
              length
              digits
              symbols
              symbolCharacters
              allowRepeat
              noUpper
              ;
          };
        };

        "${secret}-external-secret" = {
          apiVersion = "external-secrets.io/v1beta1";
          kind = "ExternalSecret";
          metadata = {
            name = secret;
            inherit namespace;
          }
          // managed;
          spec = {
            # Zero, not a schedule. A generator runs again on every refresh,
            # so anything else replaces the value underneath whatever already
            # read it.
            refreshInterval = "0";

            target = {
              name = secret;
              creationPolicy = "Owner";
            }
            // lib.optionalAttrs usesTemplate {
              template = {
                engineVersion = "v2";
                data = {
                  ${key} = if encoding == "base64" then "{{ .password | b64enc }}" else "{{ .password }}";
                }
                // extraData;
              };
            };

            dataFrom = [
              (
                {
                  sourceRef = { inherit generatorRef; };
                }
                # A template already names the key and reads `.password`, so
                # renaming the generator's output would leave it with nothing
                # to read. Only the plain, no-literals path needs the rewrite.
                // lib.optionalAttrs (!usesTemplate && key != "password") {
                  rewrite = [
                    {
                      regexp = {
                        source = "^password$";
                        target = key;
                      };
                    }
                  ];
                }
              )
            ];
          };
        };
      };

      # The key, not the Secret. external-secrets creates the Secret before it
      # has anything to put in it, so waiting on the object alone lets a
      # consumer start against an empty one.
      ready = {
        kind = "jsonpath";
        resource = "secret/${secret}";
        inherit namespace;
        jsonpath = "{.data.${key}}";
        timeout = "5m";
      };
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
      network ? { },
      imagesComplete ? false,
      assertions ? [ ],
      warnings ? [ ],
      drift ? [ ],
      steps ? { },
    }:
    {
      inherit
        bundles
        backs
        imagesComplete
        assertions
        warnings
        steps
        ;

      network = mkNetwork network;
      drift = map mkDrift drift;
    };

  mkNetwork =
    {
      declared ? false,
      serves ? { },
      reaches ? [ ],
      egress ? { },
    }:
    {
      inherit declared reaches;

      serves = lib.mapAttrs (_: s: {
        inherit (s) port;
        protocol = s.protocol or "TCP";
        fromExternal = s.fromExternal or false;
        fromApiServer = s.fromApiServer or false;
      }) serves;

      egress = {
        internet.ports = map mkPort (egress.internet.ports or [ ]);
        cidrs = map (c: {
          inherit (c) cidr;
          except = c.except or [ ];
          ports = map mkPort (c.ports or [ ]);
        }) (egress.cidrs or [ ]);
      };
    };

  mkPort =
    p:
    if lib.isInt p || lib.isString p then
      {
        port = p;
        protocol = "TCP";
      }
    else
      {
        inherit (p) port;
        protocol = p.protocol or "TCP";
      };

  mkDrift =
    {
      reason,
      group ? "",
      kinds ? [ ],
      managedBy ? [ ],
    }:
    {
      inherit
        reason
        group
        kinds
        managedBy
        ;
    };

  # ---- the monoid --------------------------------------------------------

  empty = {
    bundles = { };
    backs = { };
    network = { };
    imagesComplete = { };
    assertions = [ ];
    warnings = [ ];
    drift = [ ];
    steps = { };
  };

  # Qualify a unit's component before joining: every bundle key becomes
  # `<unit>/<bundle>`, and `needs`, which names siblings in the floe's own
  # namespace, is resolved into the same space.
  #
  # This is what makes the join total. Two floes cannot produce the same key,
  # so `//` is disjoint union — associative, with `empty` as a two-sided
  # identity, and commutative on disjoint domains.
  #
  # The design this replaced could state none of those about itself: it
  # returned an unrealised `mkMerge` and delegated the join to the module
  # system, so there was no function to reason about.
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

      # `network` and `imagesComplete` are per-floe facts, so they key on the
      # unit rather than merging: two floes' netpol declarations are two
      # declarations, and the cluster reads them side by side.
      network.${unit} = c.network;
      imagesComplete.${unit} = c.imagesComplete;

      # Keyed by unit, like `network`: the planner stamps each step with the
      # floe that declared it, so an anchor naming nothing can say which floe
      # to open.
      steps.${unit} = c.steps;

      # A failure has to name the floe that objected, which is exactly what a
      # flat list at the cluster cannot do.
      assertions = map (a: a // { message = "floe '${unit}': ${a.message}"; }) c.assertions;
      warnings = map (w: "floe '${unit}': ${w}") c.warnings;

      drift = map (d: d // { declaredBy = unit; }) c.drift;
    };

  join = a: b: {
    bundles = a.bundles // b.bundles;
    backs = a.backs // b.backs;
    network = a.network // b.network;
    imagesComplete = a.imagesComplete // b.imagesComplete;
    steps = a.steps // b.steps;
    assertions = a.assertions ++ b.assertions;
    warnings = a.warnings ++ b.warnings;
    drift = a.drift ++ b.drift;
  };

  joinAll = lib.foldl' join empty;
}
