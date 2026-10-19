{ lib, floe }:

let
  T = floe.T;

  stepType = import ../../eval/step-type.nix {
    inherit lib;
    planTokens = import ../../plan-tokens.nix { inherit lib; };
    stepKinds = import ../../step-kinds.nix { inherit lib; };
  };

  edgeTarget = {
    backend = T.str;
    httpPort = T.port;
    httpsPort = T.port;
  };
in
rec {
  KUBERNETES_CLUSTER = floe.mkSig {
    name = "KUBERNETES_CLUSTER";
    canonicalName = "cluster";
    description = "The cluster a member installs into: its name, version, context and address ranges.";
    fields = {
      name = T.k8sName;
      version = T.str;
      context = T.str;
      podSubnet = T.str;
      serviceSubnet = T.str;

      assignsLoadBalancers = T.bool;
    };
  };

  GATEWAY_API = floe.mkSig {
    name = "GATEWAY_API";
    canonicalName = "gatewayApi";
    description = "The Gateway API CRDs are registered, so Gateway and route kinds have types.";
    fields = {
      version = T.str;
      crdKinds = (T.listOf T.str);
    };
  };

  API_GATEWAY = floe.mkSig {
    name = "API_GATEWAY";
    canonicalName = "gateway";

    behaviour = [ "gateways-programmed" ];
    description = "An ingress a workload attaches an HTTPRoute to, and the zone its hostnames live in.";
    fields = {
      className = T.str;
      baseDomain = T.dnsName;
      parentRef = (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
          sectionName = T.str;
        }
      );
    };
  };

  X509_WEBHOOK = floe.mkSig {
    name = "X509_WEBHOOK";
    canonicalName = "webhook";
    description = "The certificate controller's admission webhook is serving, so its CRs are accepted.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);
    };
  };

  X509_ISSUANCE = floe.mkSig {
    name = "X509_ISSUANCE";
    canonicalName = "issuance";

    behaviour = [ "issuers-ready" ];
    description = "Something that signs certificates, and whether a browser will trust what it signs.";
    fields = {
      publicIssuer = T.bool;

      issuerRef = (
        T.record {
          name = T.str;
          kind = T.str;
        }
      );

      caSecret = (
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
    canonicalName = "trust";
    description = "A CA bundle distributed into namespaces, for workloads that verify the lab's own certificates.";
    fields = {
      namespace = T.k8sName;

      secretTargets = T.bool;

      caBundle = (
        T.record {
          name = T.str;
          key = T.str;
        }
      );

      caBundleSecret = (
        T.nullOr (
          T.record {
            name = T.str;
            key = T.str;
          }
        )
      );
    };
  };

  POSTGRES_OPERATOR = floe.mkSig {
    name = "POSTGRES_OPERATOR";
    canonicalName = "postgresOperator";
    description = "The PostgreSQL operator's CRDs are registered, so a Cluster CR has a type.";
    fields = {
      crdKinds = (T.listOf T.str);
    };
  };

  IDENTITY_OPERATOR = floe.mkSig {
    name = "IDENTITY_OPERATOR";
    canonicalName = "identityOperator";
    description = "The identity operator's CRDs are established, so its CRs can be applied.";
    fields = {
      crdsEstablished = T.str;
    };
  };

  MANAGED_RESOURCE_CONTROL_PLANE = floe.mkSig {
    name = "MANAGED_RESOURCE_CONTROL_PLANE";
    canonicalName = "controlPlane";
    description = "A control plane that installs providers and reconciles the resources they define.";
    fields = {
      namespace = T.k8sName;

      providerKind = T.str;
    };
  };

  MANAGED_RESOURCE_PROVIDER = floe.mkSig {
    name = "MANAGED_RESOURCE_PROVIDER";
    canonicalName = "resourceProvider";
    description = "A provider is healthy and the resource kinds it defines can be applied.";
    fields = {
      crdKinds = (T.listOf T.str);

      healthy = T.str;
    };
  };

  REDIS_OPERATOR = floe.mkSig {
    name = "REDIS_OPERATOR";
    canonicalName = "redisOperator";
    description = "The Redis operator's CRDs are registered, so Redis CRs have a type.";
    fields = {
      crdKinds = (T.listOf T.str);
    };
  };

  SECRET_GENERATION = floe.mkSig {
    name = "SECRET_GENERATION";
    canonicalName = "generation";
    description = "A controller that mints secret values in the cluster, so none is rendered into a manifest.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);

      generatorApiVersion = T.str;
    };
  };

  LAB_NETWORK = floe.mkSig {
    name = "LAB_NETWORK";
    canonicalName = "network";
    description = "The docker network a lab's containers share, and the gateway address on it.";
    fields = {
      name = T.str;
      subnet = T.str;

      gateway = T.str;
    };
  };

  LAB_CA = floe.mkSig {
    name = "LAB_CA";
    canonicalName = "labCa";
    description = "The lab's own root: where its certificate and key are on the host, and where it lands in a cluster.";
    fields = {
      pem = T.str;

      caCert = T.str;

      secret = T.record {
        namespace = T.k8sName;
        name = T.str;
      };
    };
  };

  OCI_MIRROR = floe.mkSig {
    name = "OCI_MIRROR";
    canonicalName = "ociMirror";
    description = "A pull-through cache on the operator's machine, as a cluster node reaches it.";
    fields = {
      name = T.str;
      port = T.port;
    };
  };

  LAB_SECRET_STORE = floe.mkSig {
    name = "LAB_SECRET_STORE";
    canonicalName = "labStore";
    description = "A store on the operator's machine that `cata` reads authored secret values from.";
    fields = {
      name = T.str;

      writable = T.bool;

      backend = T.enum [
        "sops"
        "env"
        "vault"
        "external"
      ];

      writerCommand = T.nullOr (T.listOf T.str);
      removerCommand = T.nullOr (T.listOf T.str);

      vault = T.record {
        server = T.nullOr T.str;
        path = T.str;
        version = T.enum [
          "v1"
          "v2"
        ];
      };
    };
  };

  LAB_SECRET = floe.mkSig {
    name = "LAB_SECRET";
    canonicalName = "labSecret";
    description = "A secret the lab holds on the operator's machine, and the keys a cluster may read from it.";
    fields = {
      name = T.str;

      store = T.str;

      kind = T.enum [
        "value"
        "ca"
      ];

      readableKeys = T.listOf T.str;

      keys = T.attrsOf (
        T.record {
          generator = T.nullOr (
            T.enum [
              "base64"
              "hex"
              "alphanumeric"
              "uuid"
            ]
          );
          length = T.nullOr T.int;
        }
      );

      hostPaths = T.attrsOf T.str;
    };
  };

  SECRET_STORE = floe.mkSig {
    name = "SECRET_STORE";
    canonicalName = "secretStore";
    description = "A named store an ExternalSecret reads from, and whether it may be written to.";
    fields = {

      storeName = T.str;
      storeKind = (
        T.enum [
          "SecretStore"
          "ClusterSecretStore"
        ]
      );

      writable = T.bool;
    };
  };

  PUBLISHED_SECRET = floe.mkSig {
    name = "PUBLISHED_SECRET";
    canonicalName = "publication";
    description = "A value one cluster pushed into a lab store, and where to read it.";
    fields = {
      storeName = T.str;

      key = T.str;

      keys = T.listOf T.str;
    };
  };

  CLUSTER_PROVISIONING = floe.mkSig {
    name = "CLUSTER_PROVISIONING";
    canonicalName = "provisioning";
    description = "An object in another cluster that reconciles into this one.";
    fields = {
      resourceKind = T.str;
      resourceName = T.k8sName;
    };
  };

  VAULT_SERVER = floe.mkSig {
    name = "VAULT_SERVER";
    canonicalName = "vault";
    description = "A Vault-compatible server: where it answers, its KV mount, and whether it unseals itself.";
    fields = {

      address = T.str;

      kvPath = T.str;
      kvVersion = (
        T.enum [
          "v1"
          "v2"
        ]
      );

      tokenSecret = (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );

      autoUnseals = T.bool;
    };
  };

  OIDC_PROVIDER = floe.mkSig {
    name = "OIDC_PROVIDER";
    canonicalName = "oidc";
    description = "An OIDC issuer, its endpoints, and the CR a consumer registers a client with.";
    fields = {

      issuer = T.str;

      authorizationEndpoint = T.str;
      tokenEndpoint = T.str;

      clientCrd = T.str;

      ref = (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
        }
      );

      clientsAnyNamespace = T.bool;
    };
  };

  GIT_REPOSITORY = floe.mkSig {
    name = "GIT_REPOSITORY";
    canonicalName = "git";
    description = "A git remote, addressed differently from inside and outside the cluster.";
    fields = {

      internalUrl = T.str;

      externalUrl = T.str;

      cloneUrl = T.str;

      credentials = (
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
    canonicalName = "reload";
    description = "The annotations that make a workload restart when a Secret or ConfigMap it mounts changes.";
    fields = {
      secretAnnotation = T.str;
      configMapAnnotation = T.str;
    };
  };

  STORAGE_CLASS = floe.mkSig {
    name = "STORAGE_CLASS";
    canonicalName = "storageClass";
    description = "A StorageClass a PVC can name, and whether it is the cluster's default.";
    fields = {
      className = T.str;
      isDefault = T.bool;
    };
  };

  OBJECT_STORE = floe.mkSig {
    name = "OBJECT_STORE";
    canonicalName = "objectStore";
    description = "An S3-compatible endpoint and the credentials, if any, needed to reach it.";
    fields = {
      namespace = T.k8sName;
      s3Endpoint = T.str;

      credentials = (
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
    canonicalName = "registry";
    description = "A container registry, addressed for a human and for a node pulling an image.";
    fields = {
      namespace = T.k8sName;
      url = T.str;
      pullRef = T.str;

      credentials = (
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
    canonicalName = "metrics";

    behaviour = [ "scrapes-itself" ];
    description = "Where metrics are written and queried, and the monitoring CRDs a consumer may use.";
    fields = {
      crdsEstablished = T.str;
      crdKinds = (T.listOf T.str);
      queryUrl = T.str;
      remoteWriteUrl = T.str;
    };
  };

  LOG_INGEST = floe.mkSig {
    name = "LOG_INGEST";
    canonicalName = "logs";
    description = "Where logs are pushed and queried.";
    fields = {
      pushUrl = T.str;
      queryUrl = T.str;
      otlpUrl = T.str;
    };
  };

  TRACE_INGEST = floe.mkSig {
    name = "TRACE_INGEST";
    canonicalName = "traces";
    description = "Where traces are sent and queried.";
    fields = {
      queryUrl = T.str;
      otlpGrpc = T.str;
      otlpHttp = T.str;
    };
  };

  CNI_BOOTSTRAP = floe.mkSig {
    name = "CNI_BOOTSTRAP";
    canonicalName = "cniBootstrap";
    description = "A CNI's bootstrap manifest, applied by the provisioner before the first node is Ready.";
    fields = {
      name = T.k8sName;

      manifest = T.str;
    };
  };

  CLUSTER_EDGE = floe.mkSig {
    name = "CLUSTER_EDGE";
    canonicalName = "edge";
    description = "Where a cluster's gateway is dialled from the host running the lab.";
    fields = edgeTarget;
  };

  ROUTE_CLAIM = floe.mkSig {
    name = "ROUTE_CLAIM";
    canonicalName = "route";
    description = "A public hostname this floe publishes, for whoever answers for the zone.";
    fields = {
      host = T.dnsName;
    };
  };

  LAB_STEPS = floe.mkSig {
    name = "LAB_STEPS";

    canonicalName = "step";
    description = "Plan steps a floe contributes, keyed by step name.";
    fields = {
      steps = T.attrsOf (T.named "authoredStep" (T.moduleType stepType.authoredStepType));
    };
  };

  HOST_RESOLVER = floe.mkSig {
    name = "HOST_RESOLVER";
    canonicalName = "resolver";
    description = "A resolver on the lab's network, as another container on it reaches it.";
    fields = {
      container = T.str;
    };
  };

  HOST_SERVICE = floe.mkSig {
    name = "HOST_SERVICE";
    canonicalName = "service";
    description = "A container the lab runs on the host, as `setup-services` starts it.";
    fields = {
      description = T.str;
      container = T.str;
      image = T.str;

      command = T.listOf T.str;
      ports = T.listOf T.str;
      networks = T.listOf T.str;

      dnsContainers = T.listOf T.str;

      volumes = T.attrsOf T.any;

      extraMounts = T.listOf (
        T.record {
          host = T.str;
          container = T.str;
        }
      );

      readyProbe = T.nullOr (T.attrsOf T.any);
    };
  };

  HOST_EXPOSURE = floe.mkSig {
    name = "HOST_EXPOSURE";
    canonicalName = "exposure";
    description = "The hostnames a cluster serves through the lab's edge, and where to dial them.";
    fields = {
      hosts = T.listOf T.dnsName;

      edge = T.nullOr (T.record edgeTarget);
    };
  };

  DNS_ZONE = floe.mkSig {
    name = "DNS_ZONE";
    canonicalName = "zone";
    description = "The lab's DNS zone and the server authoritative for it. The only fully portable signature.";
    fields = {
      zone = T.dnsName;

      server = T.str;
      port = T.port;
    };
  };

  MESH_NETWORK = floe.mkSig {
    name = "MESH_NETWORK";
    canonicalName = "mesh";

    description = "A mesh control plane, addressed from inside the cluster running it and from outside.";

    fields = {
      namespace = T.k8sName;

      managementUrl = T.str;
      managementInternalUrl = T.str;

      dashboardUrl = T.str;
    };
  };

  MESH_NETWORK_SHARED = floe.project {
    signature = MESH_NETWORK;
    fields = [
      "managementUrl"
      "dashboardUrl"
    ];
    description = "A mesh control plane as a cluster that does not run it can address it.";
  };

  MESH_ADMIN = floe.mkSig {
    mayExport = false;
    name = "MESH_ADMIN";
    canonicalName = "meshAdmin";
    description = "The credential that administers the mesh, as a Secret only its own cluster can read.";
    fields = {
      tokenSecret = (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );
    };
  };

  MESH_OPERATOR = floe.mkSig {
    mayExport = false;
    name = "MESH_OPERATOR";
    canonicalName = "meshOperator";
    description = "The mesh operator's CRDs are registered, and the router its resources attach to.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);

      routerRef = (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
          }
        )
      );
    };
  };

  RESOURCE_OUTPUT = floe.mkSig {
    name = "catallaxy.resourceOutput";
    canonicalName = "resourceOutput";
    description = "Readable from a declared output of another resource, once that resource exists.";
    fields = {
      resource = T.str;
      output = T.str;
    };
  };

  DELIVERY_POLICY = floe.mkSig {
    name = "DELIVERY_POLICY";
    canonicalName = "delivery";
    description = "How manifests reach the cluster, what bootstraps the applier, and how long an apply may take.";
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

      waitTimeout = T.str;

      context = T.str;
    };
  };
}
