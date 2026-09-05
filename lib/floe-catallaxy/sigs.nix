# Signatures for cluster-scope work: what a cluster offers its members, and
# what a gateway offers the workloads routing through it.
{ floe }:

let
  T = floe.T;
in
{
  # A cluster is an ordinary floe that happens to provide this. Members read
  # cluster facts through it rather than from an ambient option tree, so a
  # floe that touches one has said which.
  #
  # Every field is concrete. A manifest is rendered at build time, so a fact a
  # member interpolates has to be a decision (you choose the service CIDR) and
  # not a discovery.
  KUBERNETES_CLUSTER = floe.mkSig {
    name = "KUBERNETES_CLUSTER";
    fields = {
      name = T.k8sName;
      version = T.str;
      context = T.str;
      podSubnet = T.str;
      serviceSubnet = T.str;
    };
  };

  # Installed CRDs, as a signature.
  #
  # The shipped tree installs these through `cluster.prerequisites` rather
  # than from a floe, because gateway and cilium both need them and a bundle
  # declared twice is a conflicting definition rather than a merge — so the
  # cluster is made to own it and there is no owner left to disagree about.
  #
  # Exactly-one-provider is that rule already. Both floes require this; one
  # unit provides it; a second provider is a link error naming both. The
  # prerequisite mechanism has nothing left to do.
  GATEWAY_API = floe.mkSig {
    name = "GATEWAY_API";
    fields = {
      version = T.str;
      crdKinds = T.listOf T.str;
    };
  };

  # `parentRef` is the whole point: an HTTPRoute's attachment is a value the
  # gateway hands out, sealed to these three fields, rather than a hostname
  # and a namespace the consumer spells for itself off the gateway's options.
  #
  # This is the whole of the routing inversion. There was also a ROUTE_REQUEST
  # that the gateway collected with `requiresMany`, on the theory that the floe
  # installing a capability is the one that renders resources using it. That is
  # not how Kubernetes works — a registered CRD is a primitive anyone may use —
  # and it was not even how this tree worked: consumers already rendered their
  # own HTTPRoutes from `parentRef` below. The consumer builds one with
  # `kinds.mkRoute`, which the gateway ships.
  API_GATEWAY = floe.mkSig {
    name = "API_GATEWAY";
    fields = {
      className = T.str;
      baseDomain = T.dnsName;
      parentRef = T.record {
        name = T.k8sName;
        namespace = T.k8sName;
        sectionName = T.str;
      };
    };
  };

  # ---- x509 --------------------------------------------------------------
  #
  # cert-manager is two signatures, and the split breaks a cycle rather than
  # being a stylistic choice. In the old tree cert-manager read
  # trust-manager's export while trust-manager waited on cert-manager's
  # webhook token — a loop at floe granularity, survivable only because the
  # edges happened to sit on different bundles.
  #
  # Splitting is half the fix. The other half is turning the second edge
  # around: cert-manager no longer asks trust-manager to distribute its CA,
  # trust-manager asks cert-manager for the Secret and distributes it. That
  # is the truer arrangement anyway — handing a bundle to every namespace is
  # trust-manager's whole job, and cert-manager was only doing it because it
  # happened to know the Secret's name.
  #
  # Split and reversed, `cert-manager -> nothing` and
  # `trust-manager -> cert-manager`, which is a DAG at any granularity.

  X509_WEBHOOK = floe.mkSig {
    name = "X509_WEBHOOK";
    fields = {
      namespace = T.k8sName;
      readyToken = T.str;
      crdKinds = T.listOf T.str;
    };
  };

  X509_ISSUANCE = floe.mkSig {
    name = "X509_ISSUANCE";
    fields = {
      readyToken = T.str;
      # Whether the issuer's chain is one a public client already trusts. A
      # self-signed lab CA is not, and a consumer that cares has to be able
      # to ask rather than assume.
      publicIssuer = T.bool;
      issuerRef = T.record {
        name = T.str;
        kind = T.str;
      };

      # Where the issuer's own CA certificate lives, for whoever distributes
      # it. Null when the issuer is a public one and there is nothing to
      # distribute.
      caSecret = T.nullOr (
        T.record {
          name = T.str;
          key = T.str;
          namespace = T.k8sName;
        }
      );
    };
  };

  # Distributing a CA into every namespace that needs it. Signing and
  # distributing are different jobs with different operators, and only one of
  # them is cert-manager's.
  TRUST_BUNDLE = floe.mkSig {
    name = "TRUST_BUNDLE";
    fields = {
      readyToken = T.str;
      namespace = T.k8sName;

      # Whether a Bundle may target a Secret as well as a ConfigMap. Without
      # it a `target.secret` Bundle stays silently pending: the controller
      # starts with no Secret-write RBAC.
      secretTargets = T.bool;

      # The ConfigMap the bundle lands in, in every namespace. This is what a
      # consumer mounts to trust the lab's CA.
      caBundle = T.record {
        name = T.str;
        key = T.str;
      };

      # The same material as a Secret, for a consumer whose chart will only
      # read one — harbor's `caBundleSecret` is the case. Null when
      # `secretTargets` is false, because then the distributor has no RBAC to
      # write it and naming one would promise something that stays pending.
      #
      # It exists at all because the Secret variant was already being written
      # and its name appeared in no signature, so a consumer had to hardcode
      # `lab-ca-bundle-secret`.
      caBundleSecret = T.nullOr (
        T.record {
          name = T.str;
          key = T.str;
        }
      );
    };
  };

  # ---- operators ---------------------------------------------------------
  #
  # An operator signature says "the controller is running and will reconcile
  # this kind". A consumer applying a CR of that kind waits on it; nothing
  # else does.

  POSTGRES_OPERATOR = floe.mkSig {
    name = "POSTGRES_OPERATOR";
    fields = {
      readyToken = T.str;
      crdKinds = T.listOf T.str;
    };
  };

  IDENTITY_OPERATOR = floe.mkSig {
    name = "IDENTITY_OPERATOR";
    fields = {
      readyToken = T.str;
      crdsEstablished = T.str;
    };
  };

  REDIS_OPERATOR = floe.mkSig {
    name = "REDIS_OPERATOR";
    fields = {
      readyToken = T.str;
      crdKinds = T.listOf T.str;
    };
  };

  # Two capabilities, not one.
  #
  # These were a single `SECRET_STORE` carrying `readyToken`, `namespace` and
  # `crdKinds` — which says the controller is running, and says nothing about
  # where to pull a value from. A floe minting its own credential needs only
  # the first; a floe reading an external value needs the second, and could
  # not ask for it. Nothing required the old signature, so splitting it costs
  # nothing.

  # The external-secrets controller and its generator kinds are available, so
  # a floe may mint a credential for itself with `kinds.mkGeneratedSecret`.
  SECRET_GENERATION = floe.mkSig {
    name = "SECRET_GENERATION";
    fields = {
      readyToken = T.str;
      namespace = T.k8sName;
      crdKinds = T.listOf T.str;

      # The generator API group is versioned separately from the controller's
      # own, and a `sourceRef.generatorRef` naming the wrong one is admitted
      # and then never reconciles.
      generatorApiVersion = T.str;
    };
  };

  # A named store to pull values from, or push them to.
  #
  # Nothing provides this yet: the external-secrets floe installs a controller
  # and creates no store. It is declared now because the shape is what decides
  # whether cross-cluster sharing can be added without reworking every
  # consumer, and `storeName` is the field the old signature was missing.
  SECRET_STORE = floe.mkSig {
    name = "SECRET_STORE";
    fields = {
      readyToken = T.str;

      # What goes in an ExternalSecret's `secretStoreRef`.
      storeName = T.str;
      storeKind = T.enum [
        "SecretStore"
        "ClusterSecretStore"
      ];

      # Whether a cluster may write back into it. A store holding values
      # authored outside the lab is read-only, and a floe publishing into one
      # would be writing where nothing reads.
      writable = T.bool;
    };
  };

  # A vault-compatible KV server the lab can use as a runtime secret store.
  #
  # Distinct from SECRET_STORE, which says the external-secrets controller has
  # a store *configured* — this says where the values actually live and how to
  # authenticate to it, which is what `lab.secrets.stores.<n>.vault` needs.
  #
  # `tokenSecret` is a reference and not a token: a signature is data that
  # ends up in the rendered plan, and a credential in there is a credential in
  # the store. What mints it is a Job, so the value does not exist at eval.
  VAULT_SERVER = floe.mkSig {
    name = "VAULT_SERVER";
    fields = {
      readyToken = T.str;

      # In-cluster. A different cluster reading this store needs an address
      # that resolves outside, which is a route and therefore a lab decision.
      address = T.str;

      kvPath = T.str;
      kvVersion = T.enum [
        "v1"
        "v2"
      ];

      tokenSecret = T.record {
        namespace = T.k8sName;
        name = T.k8sName;
        key = T.str;
      };

      # Whether it comes back from a restart on its own. A shamir-sealed
      # vault does not: it needs somebody to unseal it, and a consumer that
      # waits for it to answer waits forever rather than failing. Saying so
      # is the difference between a lab that reports why it is stuck and one
      # that times out.
      autoUnseals = T.bool;
    };
  };

  # An OIDC issuer, and how to register a client with it.
  #
  # Two halves, and the split is not cosmetic. `issuer` and `scopes` are
  # generic — any OIDC provider answers them, and a consumer configures its
  # own login with nothing more. `clientCrd` and `ref` are how a *client* gets
  # created, and that is provider-specific: here it is kaniop's
  # `KanidmOAuth2Client`, reconciled by an operator watching for it.
  #
  # There is deliberately no fan-in. kaniop registers the CRD, so a client is
  # an ordinary namespaced resource and the consumer renders its own with
  # `kinds.mkOAuth2Client` — the same shape as a route through the gateway.
  # The provider does not collect requests, because a registered CRD is a
  # primitive anyone may use.
  #
  # A second provider — Keycloak, Dex — would answer `issuer` and `scopes`
  # identically and would need `mkOAuth2Client` to grow a branch on
  # `clientCrd`. That is the honest limit of how swappable this is, and it is
  # not worth abstracting until there is a second one.
  OIDC_PROVIDER = floe.mkSig {
    name = "OIDC_PROVIDER";
    fields = {
      readyToken = T.str;

      # Base issuer. A client's own discovery document hangs off it, per
      # client, which is why this is the base and not a full URL.
      issuer = T.str;

      # Where a browser is sent to log in, and where a code is exchanged.
      #
      # Both are account-level rather than per-client, which is why they are
      # here and not on what `mkOAuth2Client` returns. A consumer that does
      # its own OAuth dance rather than handing off to a library needs them
      # spelled out: netbird's management config carries an
      # `AuthorizationEndpoint` and a `TokenEndpoint` and does not read a
      # discovery document for them.
      #
      # The parked netbird floe read these off `floes.kanidm.exports`, which
      # is the by-name dependency this signature exists to remove — and it is
      # the reason they are declared even though only one consumer has ever
      # wanted them.
      authorizationEndpoint = T.str;
      tokenEndpoint = T.str;

      # `group/Kind` of the client resource, so a consumer's bundle picks up a
      # derived `kind:` edge and is ordered after whatever installs it.
      clientCrd = T.str;

      # What a client's `kanidmRef` points at.
      ref = T.record {
        name = T.k8sName;
        namespace = T.k8sName;
      };

      # Whether the server reconciles clients outside its own namespace. False
      # means a consumer's client in the consumer's namespace is silently
      # ignored — it is admitted, stored, and never reconciled — so a consumer
      # has to be told rather than left to find out.
      clientsAnyNamespace = T.bool;
    };
  };

  # Somewhere to push and clone git over HTTP.
  #
  # Two URLs, because they are read by different things and only one of them
  # resolves in both places. A CD tool running *in* the cluster clones over the
  # Service address; a human, and anything outside, needs the routed one. The
  # parked tree had a single `gitRepo` and consumers picked whichever happened
  # to work where they were tested.
  GIT_REPOSITORY = floe.mkSig {
    name = "GIT_REPOSITORY";
    fields = {
      readyToken = T.str;

      # `http://forgejo-http.forgejo.svc.cluster.local:3000`. No TLS: the
      # certificate is on the gateway, and an in-cluster client dialling the
      # Service directly would be dialling past it.
      internalUrl = T.str;

      # `https://git.lab.test`. What a clone URL in a manifest should say,
      # because a manifest is also read by people.
      externalUrl = T.str;

      # The repository itself, not the server: `https://git.lab.test/owner/lab.git`.
      #
      # Both of the above address the *server*, and everything that clones
      # needs a repository. `publish-manifests` was handed `externalUrl` and
      # cloned `https://git.gitops.test/`, which the ingress answered with a
      # 503 — there is no repository at the root. Only the floe knows what it
      # bootstrapped, so only the floe can say.
      cloneUrl = T.str;

      # Which keys, not just which Secret — the same reason OCI_REGISTRY
      # carries them. Null when the server takes anonymous reads.
      credentials = T.nullOr (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
          # The username itself, not just where to read it. A username is not
          # a secret, and the thing that pushes needs it as a literal — it
          # goes into a URL, not into a Secret lookup. Passing `usernameKey`
          # here authenticated as a user called "username".
          username = T.str;

          usernameKey = T.str;
          passwordKey = T.str;
        }
      );
    };
  };

  # Workload reload on Secret/ConfigMap rotation. The two annotation keys are
  # the interface; the old floe also exported a `mkPatches` *function*, which
  # a signature cannot carry and which `lib/k8s-annotations.nix` replaces.
  CONFIG_RELOAD = floe.mkSig {
    name = "CONFIG_RELOAD";
    fields = {
      readyToken = T.str;
      secretAnnotation = T.str;
      configMapAnnotation = T.str;
    };
  };

  # ---- storage and telemetry ---------------------------------------------

  STORAGE_CLASS = floe.mkSig {
    name = "STORAGE_CLASS";
    fields = {
      readyToken = T.str;
      className = T.str;
      isDefault = T.bool;
    };
  };

  OBJECT_STORE = floe.mkSig {
    name = "OBJECT_STORE";
    fields = {
      readyToken = T.str;
      namespace = T.k8sName;
      s3Endpoint = T.str;

      # Where the keys to reach that endpoint are.
      #
      # An address with no credential is not a usable capability: a consumer
      # given only `s3Endpoint` has to find the chart's generated keys by
      # reading its templates, which is exactly the hardcoding a signature
      # exists to remove. Null for a store that genuinely needs none.
      credentials = T.nullOr (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
          accessKeyKey = T.str;
          secretKeyKey = T.str;
        }
      );
    };
  };

  # A registry inside the cluster that can hold images.
  #
  # `pullRef` is the field that matters and the one a consumer gets wrong: an
  # image reference needs `host:port` with no scheme, which is a different
  # string from the URL something dials over HTTP. Carrying both means a
  # consumer never has to strip one to make the other.
  OCI_REGISTRY = floe.mkSig {
    name = "OCI_REGISTRY";
    fields = {
      readyToken = T.str;
      namespace = T.k8sName;
      url = T.str;
      pullRef = T.str;

      # Null when the registry takes anything. A consumer pushing to one that
      # does not has to know before it tries, and finding out from a 401 in a
      # Job's logs is finding out too late.
      credentials = T.nullOr (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;

          # Which keys, not just which Secret. A consumer that knows the
          # Secret and guesses the keys fails at pull time with a 401, which
          # is the same "finding out too late" the field above exists to
          # prevent — and every registry spells them differently.
          usernameKey = T.str;
          passwordKey = T.str;
        }
      );
    };
  };

  # Somewhere to send metrics, and the kinds needed to ask for them.
  #
  # `crdsEstablished` is separate from `readyToken` because they gate different
  # things and become true at different times. A floe emitting a
  # `ServiceMonitor` needs the kind to exist; a floe that *writes* metrics
  # needs the receiver to be up. Collapsing them makes the first wait on the
  # second for no reason.
  METRICS_INGEST = floe.mkSig {
    name = "METRICS_INGEST";
    fields = {
      readyToken = T.str;
      crdsEstablished = T.str;
      crdKinds = T.listOf T.str;
      queryUrl = T.str;
      remoteWriteUrl = T.str;
    };
  };

  LOG_INGEST = floe.mkSig {
    name = "LOG_INGEST";
    fields = {
      readyToken = T.str;
      pushUrl = T.str;
      queryUrl = T.str;
      otlpUrl = T.str;
    };
  };

  TRACE_INGEST = floe.mkSig {
    name = "TRACE_INGEST";
    fields = {
      readyToken = T.str;
      queryUrl = T.str;
      otlpGrpc = T.str;
      otlpHttp = T.str;
    };
  };

  # An overlay network peers join, and the control plane that admits them.
  #
  # Two URLs for the same server, as `GIT_REPOSITORY` has: a peer outside the
  # cluster registers over the routed name, and an in-cluster consumer — the
  # operator that manages mesh state, the agent that joins the cluster to it —
  # dials the Service, because the routed name leaves the cluster and comes
  # back through the ingress to reach a pod one hop away.
  #
  # What is deliberately absent is anything about *joining*: no setup key, no
  # group. Those are the operator's, and the operator is the layer of this
  # floe that is not built yet — so the fields would be promises with nothing
  # behind them.
  MESH_NETWORK = floe.mkSig {
    name = "MESH_NETWORK";

    # The point of a mesh is that it spans clusters, so this is the first
    # signature to cross a link boundary. `managementUrl` is what makes it
    # legitimate: a consumer in another cluster reaches the control plane over
    # the routed name, exactly as a peer on a laptop does.
    crossCluster = true;

    fields = {
      readyToken = T.str;
      namespace = T.k8sName;

      managementUrl = T.str;
      managementInternalUrl = T.str;

      # The UI, which is the same origin as the API: netbird routes all of it
      # by path off one hostname. A field of its own anyway, because a mesh
      # implementation that split them would still have to answer this.
      dashboardUrl = T.str;
    };
  };

  # How the cluster's manifests reach it. A policy value rather than a
  # component: nothing installs it, and the floes that read it are choosing
  # between rendering for a CD tool and rendering for a direct apply.
  DELIVERY_POLICY = floe.mkSig {
    name = "DELIVERY_POLICY";
    fields = {
      strategy = T.enum [
        "kapp"
        "argocd"
        "fleet"
      ];
      bootstrapTool = T.enum [
        "kubectl-ssa"
        "helm"
        "none"
      ];
      appliedByKapp = T.bool;
    };
  };
}
