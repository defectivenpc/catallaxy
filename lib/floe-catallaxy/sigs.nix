# Signatures for cluster-scope work: what a cluster offers its members, and
# what a gateway offers the workloads routing through it.
{ floe }:

let
  T = floe.T;
in
{
  KUBERNETES_CLUSTER = floe.mkSig {
    name = "KUBERNETES_CLUSTER";
    as = "cluster";
    description = "The cluster a member installs into: its name, version, context and address ranges.";
    fields = {
      name = T.local T.k8sName;
      version = T.local T.str;
      context = T.local T.str;
      podSubnet = T.local T.str;
      serviceSubnet = T.local T.str;

      assignsLoadBalancers = T.local T.bool;
    };
  };

  GATEWAY_API = floe.mkSig {
    name = "GATEWAY_API";
    as = "gatewayApi";
    description = "The Gateway API CRDs are registered, so Gateway and route kinds have types.";
    fields = {
      version = T.local T.str;
      crdKinds = T.local (T.listOf T.str);
    };
  };

  API_GATEWAY = floe.mkSig {
    name = "API_GATEWAY";
    as = "gateway";
    description = "An ingress a workload attaches an HTTPRoute to, and the zone its hostnames live in.";
    fields = {
      className = T.local T.str;
      baseDomain = T.dnsName;
      parentRef = T.local (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
          sectionName = T.str;
        }
      );
    };
  };

  # ---- x509 --------------------------------------------------------------

  X509_WEBHOOK = floe.mkSig {
    name = "X509_WEBHOOK";
    as = "webhook";
    description = "The certificate controller's admission webhook is serving, so its CRs are accepted.";
    fields = {
      namespace = T.local T.k8sName;
      crdKinds = T.local (T.listOf T.str);
    };
  };

  X509_ISSUANCE = floe.mkSig {
    name = "X509_ISSUANCE";
    as = "issuance";
    description = "Something that signs certificates, and whether a browser will trust what it signs.";
    fields = {
      publicIssuer = T.bool;

      # A ClusterIssuer object in this cluster. A Certificate elsewhere naming
      # it stays pending forever against an issuer that does not exist.
      issuerRef = T.local (
        T.record {
          name = T.str;
          kind = T.str;
        }
      );

      caSecret = T.local (
        T.nullOr (
          T.record {
            name = T.str;
            key = T.str;
            namespace = T.k8sName;
          }
        )
      );
    };
  };

  TRUST_BUNDLE = floe.mkSig {
    name = "TRUST_BUNDLE";
    as = "trust";
    description = "A CA bundle distributed into namespaces, for workloads that verify the lab's own certificates.";
    fields = {
      namespace = T.local T.k8sName;

      secretTargets = T.local T.bool;

      # The ConfigMap the bundle lands in, in every namespace. This is what a
      # consumer mounts to trust the lab's CA.
      caBundle = T.local (
        T.record {
          name = T.str;
          key = T.str;
        }
      );

      caBundleSecret = T.local (
        T.nullOr (
          T.record {
            name = T.str;
            key = T.str;
          }
        )
      );
    };
  };

  # ---- operators ---------------------------------------------------------

  POSTGRES_OPERATOR = floe.mkSig {
    name = "POSTGRES_OPERATOR";
    as = "postgresOperator";
    description = "The PostgreSQL operator's CRDs are registered, so a Cluster CR has a type.";
    fields = {
      crdKinds = T.local (T.listOf T.str);
    };
  };

  IDENTITY_OPERATOR = floe.mkSig {
    name = "IDENTITY_OPERATOR";
    as = "identityOperator";
    description = "The identity operator's CRDs are established, so its CRs can be applied.";
    fields = {
      crdsEstablished = T.local T.str;
    };
  };

  # ---- managed resources -------------------------------------------------

  MANAGED_RESOURCE_CONTROL_PLANE = floe.mkSig {
    name = "MANAGED_RESOURCE_CONTROL_PLANE";
    as = "controlPlane";
    description = "A control plane that installs providers and reconciles the resources they define.";
    fields = {
      namespace = T.local T.k8sName;

      # The kind a provider floe renders to install itself, so a provider
      # names no product either. Rendering it is also what orders the provider
      # after these CRDs: `elaborate.nix` derives a `kind:` edge from the
      # bundle that declares them, so there is no token to publish.
      providerKind = T.local T.str;
    };
  };

  MANAGED_RESOURCE_PROVIDER = floe.mkSig {
    name = "MANAGED_RESOURCE_PROVIDER";
    as = "resourceProvider";
    description = "A provider is healthy and the resource kinds it defines can be applied.";
    fields = {
      crdKinds = T.local (T.listOf T.str);

      # What a consumer orders against: the provider's CRDs arrive when it
      # installs, which is well after the CR that installed it was applied.
      healthy = T.local T.str;
    };
  };

  REDIS_OPERATOR = floe.mkSig {
    name = "REDIS_OPERATOR";
    as = "redisOperator";
    description = "The Redis operator's CRDs are registered, so Redis CRs have a type.";
    fields = {
      crdKinds = T.local (T.listOf T.str);
    };
  };

  # The external-secrets controller and its generator kinds are available, so
  # a floe may mint a credential for itself with `kinds.mkGeneratedSecret`.
  SECRET_GENERATION = floe.mkSig {
    name = "SECRET_GENERATION";
    as = "generation";
    description = "A controller that mints secret values in the cluster, so none is rendered into a manifest.";
    fields = {
      namespace = T.local T.k8sName;
      crdKinds = T.local (T.listOf T.str);

      generatorApiVersion = T.local T.str;
    };
  };

  SECRET_STORE = floe.mkSig {
    name = "SECRET_STORE";
    as = "secretStore";
    description = "A named store an ExternalSecret reads from, and whether it may be written to.";
    fields = {

      # What goes in an ExternalSecret's `secretStoreRef`.
      storeName = T.local T.str;
      storeKind = T.local (
        T.enum [
          "SecretStore"
          "ClusterSecretStore"
        ]
      );

      writable = T.local T.bool;
    };
  };

  VAULT_SERVER = floe.mkSig {
    name = "VAULT_SERVER";
    as = "vault";
    description = "A Vault-compatible server: where it answers, its KV mount, and whether it unseals itself.";
    fields = {

      # In-cluster. A different cluster reading this store needs an address
      # that resolves outside, which is a route and therefore a lab decision.
      address = T.str;

      kvPath = T.local T.str;
      kvVersion = T.local (
        T.enum [
          "v1"
          "v2"
        ]
      );

      tokenSecret = T.local (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );

      autoUnseals = T.local T.bool;
    };
  };

  OIDC_PROVIDER = floe.mkSig {
    name = "OIDC_PROVIDER";
    as = "oidc";
    description = "An OIDC issuer, its endpoints, and the CR a consumer registers a client with.";
    fields = {

      # Base issuer. A client's own discovery document hangs off it, per
      # client, which is why this is the base and not a full URL.
      issuer = T.str;

      authorizationEndpoint = T.str;
      tokenEndpoint = T.str;

      # `group/Kind` of the client resource, so a consumer's bundle picks up a
      # derived `kind:` edge and is ordered after whatever installs it.
      clientCrd = T.local T.str;

      # What a client's `kanidmRef` points at.
      ref = T.local (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
        }
      );

      clientsAnyNamespace = T.local T.bool;
    };
  };

  GIT_REPOSITORY = floe.mkSig {
    name = "GIT_REPOSITORY";
    as = "git";
    description = "A git remote, addressed differently from inside and outside the cluster.";
    fields = {

      internalUrl = T.local T.str;

      # `https://git.lab.test`. What a clone URL in a manifest should say,
      # because a manifest is also read by people.
      externalUrl = T.str;

      cloneUrl = T.str;

      # Which keys, not just which Secret — the same reason OCI_REGISTRY
      # carries them. Null when the server takes anonymous reads.
      credentials = T.local (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
            username = T.str;

            usernameKey = T.str;
            passwordKey = T.str;
          }
        )
      );
    };
  };

  CONFIG_RELOAD = floe.mkSig {
    name = "CONFIG_RELOAD";
    as = "reload";
    description = "The annotations that make a workload restart when a Secret or ConfigMap it mounts changes.";
    fields = {
      secretAnnotation = T.local T.str;
      configMapAnnotation = T.local T.str;
    };
  };

  # ---- storage and telemetry ---------------------------------------------

  STORAGE_CLASS = floe.mkSig {
    name = "STORAGE_CLASS";
    as = "storageClass";
    description = "A StorageClass a PVC can name, and whether it is the cluster's default.";
    fields = {
      className = T.local T.str;
      isDefault = T.local T.bool;
    };
  };

  OBJECT_STORE = floe.mkSig {
    name = "OBJECT_STORE";
    as = "objectStore";
    description = "An S3-compatible endpoint and the credentials, if any, needed to reach it.";
    fields = {
      namespace = T.local T.k8sName;
      s3Endpoint = T.local T.str;

      credentials = T.local (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
            accessKeyKey = T.str;
            secretKeyKey = T.str;
          }
        )
      );
    };
  };

  OCI_REGISTRY = floe.mkSig {
    name = "OCI_REGISTRY";
    as = "registry";
    description = "A container registry, addressed for a human and for a node pulling an image.";
    fields = {
      namespace = T.local T.k8sName;
      url = T.str;
      pullRef = T.local T.str;

      credentials = T.local (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;

            usernameKey = T.str;
            passwordKey = T.str;
          }
        )
      );
    };
  };

  METRICS_INGEST = floe.mkSig {
    name = "METRICS_INGEST";
    as = "metrics";
    description = "Where metrics are written and queried, and the monitoring CRDs a consumer may use.";
    fields = {
      crdsEstablished = T.local T.str;
      crdKinds = T.local (T.listOf T.str);
      queryUrl = T.local T.str;
      remoteWriteUrl = T.local T.str;
    };
  };

  LOG_INGEST = floe.mkSig {
    name = "LOG_INGEST";
    as = "logs";
    description = "Where logs are pushed and queried.";
    fields = {
      pushUrl = T.local T.str;
      queryUrl = T.local T.str;
      otlpUrl = T.local T.str;
    };
  };

  TRACE_INGEST = floe.mkSig {
    name = "TRACE_INGEST";
    as = "traces";
    description = "Where traces are sent and queried.";
    fields = {
      queryUrl = T.local T.str;
      otlpGrpc = T.local T.str;
      otlpHttp = T.local T.str;
    };
  };

  DNS_ZONE = floe.mkSig {
    name = "DNS_ZONE";
    as = "zone";
    description = "The lab's DNS zone and the server authoritative for it. The only fully portable signature.";
    fields = {
      # `lab.test`, no trailing dot: it is both the zone and the suffix every
      # routed hostname hangs off.
      zone = T.dnsName;

      server = T.str;
      port = T.port;
    };
  };

  MESH_NETWORK = floe.mkSig {
    name = "MESH_NETWORK";
    as = "mesh";
    description = "A mesh control plane, addressed from inside the cluster running it and from outside.";

    fields = {
      namespace = T.local T.k8sName;

      managementUrl = T.str;
      managementInternalUrl = T.local T.str;

      dashboardUrl = T.str;
    };
  };

  MESH_ADMIN = floe.mkSig {
    name = "MESH_ADMIN";
    as = "meshAdmin";
    description = "The credential that administers the mesh, as a Secret only its own cluster can read.";
    fields = {
      tokenSecret = T.local (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );
    };
  };

  MESH_OPERATOR = floe.mkSig {
    name = "MESH_OPERATOR";
    as = "meshOperator";
    description = "The mesh operator's CRDs are registered, and the router its resources attach to.";
    fields = {
      namespace = T.local T.k8sName;
      crdKinds = T.local (T.listOf T.str);

      routerRef = T.local (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
          }
        )
      );
    };
  };

  DELIVERY_POLICY = floe.mkSig {
    name = "DELIVERY_POLICY";
    as = "delivery";
    description = "How manifests reach the cluster, and what bootstraps whatever applies them.";
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
    };
  };
}
