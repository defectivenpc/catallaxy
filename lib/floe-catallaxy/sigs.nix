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
