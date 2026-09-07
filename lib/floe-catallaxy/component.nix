# What a cluster-component floe contributes, and the monoid that joins two of
# them. One kind, so every component floe has the same output type and the
# cluster picture is a fold rather than a pile.
{ lib, floe }:

let
  T = floe.T;

  inherit (import ../eval/secret-refs.nix { inherit lib; }) secretAddress;
  inherit (import ../kubernetes/labels.nix { }) catallaxyManaged;

  schemas = import ./component-schema.nix { inherit lib floe; };
  inherit (schemas)
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

  # point someone writes it, which is the only place they can act on it.
  mkImage =
    ref:
    let
      atParts = lib.splitString "@" ref;
      beforeDigest = lib.head atParts;
      digest = if lib.length atParts > 1 then lib.last atParts else null;

      # Rightmost colon, because a registry may carry a port and a tag may not
      # contain one.
      slashParts = lib.splitString "/" beforeDigest;
      registry = lib.head slashParts;
      rest = lib.concatStringsSep "/" (lib.tail slashParts);
      colonParts = lib.splitString ":" rest;
      repository = lib.head colonParts;
      tag = if lib.length colonParts > 1 then lib.last colonParts else null;
    in
    if lib.length slashParts < 2 || !(lib.hasInfix "." registry || lib.hasInfix ":" registry) then
      throw (
        "image '${ref}': needs an explicit registry. A first segment with no dot or port is a "
        + "Docker Hub namespace, so `traefik` and `docker.io/traefik` are the same image spelled "
        + "two ways — and a floe's declaration is compared against what its manifests actually "
        + "pull, where only one of the two appears."
      )
    else
      {
        inherit
          registry
          repository
          tag
          digest
          ;
      };
  # parenthesised — `|` binds looser than `&&`, so the unparenthesised form
  # parses as a pipeline and evaluates to nonsense instead of erroring. There
  # is one correct spelling and it already exists; re-exported so a floe
  # author reaches it through `kinds` rather than writing it out.
  verifyTypes = import ../verify-types.nix { inherit lib; };
in
rec {
  component = floe.mkOutputKind {
    name = "catallaxy.component";
    description = "What a floe installs into a cluster: bundles, and the operator surface around them.";
    schema = componentSchema;
  };

  inherit (verifyTypes) conditionIsNot fieldIsNot;
  inherit mkImage;

  # A readiness probe, for the shape 26 of 32 bundles were writing out.
  #
  # The timeout defaults and every other value is written down, which turns
  # "3m, 5m and 10m with no stated rule" into a column a reader can audit —
  # `docs/floes/<name>.md` shows every bundle's probe at a glance, so a floe
  # waiting ten minutes is now visibly waiting ten minutes *on purpose*.
  readyCondition =
    {
      resource,
      condition,
      namespace ? null,
      timeout ? "5m",
    }:
    {
      kind = "condition";
      inherit resource condition timeout;
    }
    // lib.optionalAttrs (namespace != null) { inherit namespace; };

  # The overwhelmingly common one: a Deployment reporting Available.
  readyDeployment =
    {
      name,
      namespace,
      timeout ? "5m",
    }:
    {
      kind = "condition";
      resource = "deployment/${name}";
      condition = "Available";
      inherit namespace timeout;
    };

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
      routedHosts ? [ ],
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
        routedHosts
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
          labels = catallaxyManaged;
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
            labels = catallaxyManaged;
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

  # A machine identity: an account no human logs into, with an API token a
  # workload authenticates as.
  #
  # This is the piece that turns "click a setup key in the dashboard" into
  # something a lab declares. A controller that has to call an API on the
  # lab's behalf needs an identity, and until this the only way to give it one
  # was to make it by hand and paste the result into a Secret — which is not a
  # deployment, it is a runbook.
  #
  # kaniop mints both the account and the token, and rotates the token on a
  # period. That is the whole reason this is a CR rather than a Job: an
  # expiring credential that something else owns is a credential that heals.
  #
  # `secretName` on a token is settable, so unlike the OAuth2 client's Secret
  # there is no operator convention to encode here — the floe says where it
  # wants the token and reads it back from the same place.
  mkServiceAccount =
    {
      provider,
      name,
      namespace,
      tokenSecret,
      displayName ? name,
      # `readwrite`, because the point of one of these is to change something.
      # A read-only identity is a legitimate thing to want and says so.
      purpose ? "readwrite",
      rotationDays ? 30,

      # Who may administer this account. Required by the CRD and not
      # defaultable to something clever: kanidm's built-in admin group is the
      # only principal a freshly-bootstrapped lab is guaranteed to have, and a
      # lab that delegates the account elsewhere says so.
      managedBy ? "idm_admins",
    }:
    let
      group = lib.head (lib.splitString "/" provider.clientCrd);
    in
    if !provider.clientsAnyNamespace && namespace != provider.ref.namespace then
      # The same refusal `mkOAuth2Client` makes, for the same reason and with
      # the same symptom: admitted, stored, never reconciled, and a consumer
      # waiting on a token that is not coming.
      throw ''
        service account '${name}' is in namespace '${namespace}', and the
        identity provider only reconciles accounts in its own
        ('${provider.ref.namespace}').

        Nothing would report this: the resource is admitted and then ignored,
        its status stays empty, and the token it should mint never appears.
      ''
    else
      {
        resource = {
          apiVersion = "${group}/v1beta1";
          kind = "KanidmServiceAccount";
          metadata = {
            inherit name namespace;
            labels = catallaxyManaged;
          };
          spec = {
            kanidmRef = provider.ref;
            serviceAccountAttributes = {
              displayname = displayName;
              entryManagedBy = managedBy;
            };

            apiTokens = [
              {
                label = displayName;
                inherit purpose;
                secretName = tokenSecret;
              }
            ];

            # Rotated by the operator that issued it. A consumer re-reads the
            # Secret; anything holding the old value gets a 401 and is expected
            # to look again, which is why the things that read one are also the
            # things that heal.
            apiTokenRotation = {
              enabled = true;
              periodDays = rotationDays;
            };
          };
        };

        # Where the token lands. The Secret's name is ours — `secretName` is
        # a field on the token — and the key is kaniop's: a flat `token`,
        # established by applying one and reading the Secret back, because the
        # CRD documents the Secret's name and says nothing about what is in
        # it. It was guessed as the token's label first, and the guess cost a
        # deploy.
        #
        # One token per Secret follows: two `apiTokens` sharing a `secretName`
        # would write the same key twice and the second would win silently.
        token = {
          inherit namespace;
          name = tokenSecret;
          key = "token";
        };

        # The Secret exists only once kaniop has reconciled the account *and*
        # issued the token, which is two round trips after the CR is applied.
        # Waiting on the object alone would let a consumer start against an
        # empty one.
        ready = {
          kind = "jsonpath";
          resource = "secret/${tokenSecret}";
          inherit namespace;
          jsonpath = "{.data.token}";
          timeout = "5m";
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

      managed.labels = catallaxyManaged;
    in
    {
      # The ExternalSecret's target is readable off `resources`, so this is
      # belt and braces — but a floe reading its own generated credential
      # through a Helm value has no other way to be believed.
      secrets = [ (secretAddress namespace secret) ];

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

      drift = map mkDrift drift;
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

      # `imagesComplete` is a per-floe fact, so it keys on the
      # unit rather than merging: two floes' netpol declarations are two
      # declarations, and the cluster reads them side by side.
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
    imagesComplete = a.imagesComplete // b.imagesComplete;
    steps = a.steps // b.steps;
    assertions = a.assertions ++ b.assertions;
    warnings = a.warnings ++ b.warnings;
    drift = a.drift ++ b.drift;
  };

  joinAll = lib.foldl' join empty;
}
