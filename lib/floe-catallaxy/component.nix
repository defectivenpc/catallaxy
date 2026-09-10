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

        oidc = {
          clientId = name;
          issuer = "${provider.issuer}/oauth2/openid/${name}";
          jwksUri = "${provider.issuer}/oauth2/openid/${name}/public_key.jwk";
          discoveryUrl = "${provider.issuer}/oauth2/openid/${name}/.well-known/openid-configuration";
          inherit (provider) authorizationEndpoint tokenEndpoint;
        };

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

      managedBy ? "idm_admins",
    }:
    let
      group = lib.head (lib.splitString "/" provider.clientCrd);
    in
    if !provider.clientsAnyNamespace && namespace != provider.ref.namespace then
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

            apiTokenRotation = {
              enabled = true;
              periodDays = rotationDays;
            };
          };
        };

        token = {
          inherit namespace;
          name = tokenSecret;
          key = "token";
        };

        ready = {
          kind = "jsonpath";
          resource = "secret/${tokenSecret}";
          inherit namespace;
          jsonpath = "{.data.token}";
          timeout = "5m";
        };
      };

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
      encoding ? "plain",
      extraData ? { },
    }:
    let
      generatorRef = {
        apiVersion = "generators.external-secrets.io/v1alpha1";
        kind = "Password";
        name = secret;
      };

      usesTemplate = encoding == "base64" || extraData != { };

      managed.labels = catallaxyManaged;
    in
    {
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

      backs = lib.mapAttrs' (n: bs: lib.nameValuePair (key n) (map key bs)) c.backs;

      imagesComplete.${unit} = c.imagesComplete;

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
