# Signatures for cluster-scope work: what a cluster offers its members, and
# what a gateway offers the workloads routing through it.
{ floe }:

let
  T = floe.T;

  # Where a cluster's gateway is dialled, shared by the signature the
  # provisioner answers and the field a cluster's exposure carries it in. One
  # record, so the thing that knows the address and the thing that routes to
  # it cannot describe it differently.
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

  # ---- x509 --------------------------------------------------------------

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

  # ---- operators ---------------------------------------------------------

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

  # ---- managed resources -------------------------------------------------

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

  # The external-secrets controller and its generator kinds are available, so
  # a floe may mint a credential for itself with `kinds.mkGeneratedSecret`.
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

  # The docker network every container in this lab shares, and the addresses
  # on it.
  #
  # A fact the lab holds and no floe can derive: which network a container
  # joins is a statement about what else is on the host. It was threaded as
  # three inputs into four floes — `network = lab.name` into the proxy, the
  # resolver and the egress, `server = lab.network.gateway` into the zone —
  # and there is a floe that *is* the network now, which is what makes the
  # threading an asymmetry rather than the merge surface doing its job.
  #
  # It buys no ordering: `setup-services` is after `lab/network` by an anchor,
  # and anchors are a different graph from the link's.
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

  # The lab's own certificate authority: what signs for `*.<zone>` and what a
  # cluster's issuer signs from.
  #
  # It was a `rootFromLab` boolean on `cert-manager`, whose description said
  # "set it exactly when `lab.proxy.tls.enable` is on" — a prose instruction
  # with nothing checking it — beside an assertion comparing a hardcoded
  # `cert-manager/lab-ca-ca-secret` against what the CLI writes, because
  # nothing in the floe system could relate a Nix string to a Rust literal.
  # Resolving this is both statements at once.
  #
  # The paths mirror what `cli/src/host/pki.rs` writes, the way a k3d
  # descriptor's `nodeConfigFrom` mirrors a state directory. They are declared
  # here so the one floe that mounts the certificate reads it off the thing
  # that mints it rather than spelling the path a second time.
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

  # A pull-through cache on the operator's machine that cluster nodes pull
  # images from.
  #
  # Not `OCI_REGISTRY`, which is a registry *in* a cluster addressed by
  # `namespace`, `url`, `pullRef` and `credentials`. A host mirror is neither
  # in a cluster nor addressed that way: a node reaches it by a containerd
  # config file bind-mounted at creation, and the thing that writes that file
  # is the CLI.
  #
  # `name` is the providing floe's unit name, which is also its state
  # directory — so a provisioner that resolves this carries the directory in
  # its descriptor and `create_cluster` is *told* where the node config is.
  # It used to join `service_state_dir(lab, "registry")` from a literal and
  # probe for the files, which made mirroring something discovered on the
  # filesystem at deploy rather than something a cluster declared.
  #
  # `talos-cluster` declares no hole for it, which is the whole of why a Talos
  # lab does not mirror: talosctl takes machine config rather than bind
  # mounts, so there is no path for the file to arrive on. That was
  # `lab.registry.enable = mkForce false` under a paragraph of explanation.
  OCI_MIRROR = floe.mkSig {
    name = "OCI_MIRROR";
    canonicalName = "ociMirror";
    description = "A pull-through cache on the operator's machine, as a cluster node reaches it.";
    fields = {
      name = T.str;
      port = T.port;
    };
  };

  # A store on the operator's machine, which `cata` reads and writes.
  #
  # Not `SECRET_STORE`, which is the in-cluster `SecretStore` CR an
  # ExternalSecret reads from. Nothing about this one is in a cluster: it is a
  # sops file, a set of environment variables, or a vault somewhere else, and
  # the thing that opens it is the CLI. Same split as `OCI_MIRROR` against
  # `OCI_REGISTRY`.
  #
  # `name` is what `cata secrets edit <name>` takes, and it is the providing
  # floe's unit name — so a consumer resolves the store rather than spelling
  # it. Five places used to spell it: a projection's `source`, a
  # publication's `store`, and the kubeconfig coordinates on `doks`,
  # `provisioned` and `external-cluster`. None of them was checked.
  # Everything the store floe knows, at the width each reader needs.
  #
  # A peer resolving this reads `name` and `writable`; `lab-secrets` folds the
  # whole record into the one thing the CLI reads. One statement at two widths
  # rather than a signature beside an output kind — the floe emitted both, and
  # the fold of the kind could not be a floe because an output kind is folded
  # by whoever holds the link.
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

  # One secret the lab holds, and the keys in it.
  #
  # What a cluster projects. `secret-projection` named this by string —
  # `source = "<name>"`, matching an attribute under `lab.secrets.managed`
  # with nothing checking it — and a typo left a Secret that `cata` had no
  # values for, waiting forever on a key nothing would write.
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

  # Where a value one cluster minted is readable from, once it has pushed it.
  #
  # The whole of cross-cluster secret sharing, as one value on one link edge.
  # It was a pair of lab options — `secrets.publish` on the producer and
  # `secrets.subscribe` on the consumer — with five assertion families
  # checking that both sides had derived the same address from the producer's
  # identity. Nothing negotiated, and nothing checked at runtime either: a
  # name that did not match on both sides left an ExternalSecret waiting
  # forever on a key nothing wrote.
  #
  # The producer names the key and provides it; the consumer reads it. There
  # is no address scheme and nothing for an assertion to compare.
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

  # One cluster bringing another into existence, from the managing side.
  #
  # The coordinates of the object that represents the cluster: a Crossplane
  # claim, a Cluster API resource, whatever reconciles into a cluster. Held
  # by a floe in the cluster that *runs* the controller, and read by the
  # cluster that is the result — which is the direction that makes it a
  # signature rather than a declaration. A cluster naming what creates it
  # would be a container's provisions depending on its contents.
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

  # ---- storage and telemetry ---------------------------------------------

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

  # What a provisioner has to apply before any node can become Ready, so the
  # cluster it establishes can have a CNI that is not the one it ships with.
  #
  # This is the direction the link graph used to lack. `k3d-cluster` carried a
  # `disableFlannel` input and cilium exported a `mkBootstrapManifest`
  # function, and a lab had to set both consistently — three of cilium's
  # inputs said "must match what `mkBootstrapManifest` was given", and setting
  # one half alone gave either nodes that never come up or two CNIs writing
  # over each other's datapath rules. Nothing could check it.
  #
  # It works now because a claim is a unit *beside* its cluster rather than
  # inside it: the cluster exports what its CNI floe provides, and the
  # provisioner resolves it like any other hole. The manifest is a derivation
  # path, which does not depend on the claim, so the two-unit cycle is legal —
  # the same shape as the NixOS example's `nginx` and `networking`.
  CNI_BOOTSTRAP = floe.mkSig {
    name = "CNI_BOOTSTRAP";
    canonicalName = "cniBootstrap";
    description = "A CNI's bootstrap manifest, applied by the provisioner before the first node is Ready.";
    fields = {
      name = T.k8sName;

      manifest = T.str;
    };
  };

  # A public hostname a floe publishes, claimed rather than discovered.
  #
  # The gateway collects these and a cluster exports the aggregate, which is
  # how a resolver on the host learns what to answer for without reading any
  # cluster's elaborated output — a thing it cannot do, because it is a unit of
  # the same link. ADR 0004.
  # Where this cluster is reachable from the machine the lab runs on.
  #
  # The provisioner's answer, and only the provisioner can give it: every
  # backend is built from the container-naming convention of the tool that
  # created the cluster, and the ports are whether that distribution has
  # something binding 80 and 443 on a node. A cluster nobody here created
  # answers nothing, which is why a consumer takes this as an optional hole.
  #
  # Not a field of `KUBERNETES_CLUSTER`: that is what a member installing into
  # a cluster reads, every field of it is always real, and an address reached
  # from outside has one consumer.
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

  # Plan steps a floe contributes, and the two conditions it may say them
  # under.
  #
  # A signature for the same reason `HOST_SERVICE` is one: the contributions
  # stay distinct, keyed by the floe that made them, and `lab-steps` folds
  # them. It was `catallaxy.labSteps`, an output kind, which left the fold to
  # whoever held the link.
  #
  # What a floe may say about *when* is the interesting half. It has no name
  # for a cluster it is not in and none for its peers, so it cannot write an
  # anchor naming one — `floes/lab/registry.nix` has to run before every
  # cluster is created and cannot spell a single cluster's token. So it states
  # a condition and `lab-steps`, which collects the claims and therefore knows
  # the clusters, turns it into one anchor each:
  #
  #   beforeClusters = "created";    # before every cluster reaches `created`
  #   afterClusters  = "destroyed";  # after every cluster reaches `destroyed`
  #
  # That is the whole vocabulary, deliberately. A floe that cannot say what it
  # means with these two should make the gap visible rather than reach for an
  # escape hatch that lets it say anything.
  LAB_STEPS = floe.mkSig {
    name = "LAB_STEPS";

    canonicalName = "step";
    description = "Plan steps a floe contributes, keyed by step name.";
    fields = {
      steps = T.attrsOf (T.attrsOf T.any);
    };
  };

  # A container the lab runs on the operator's machine.
  #
  # A signature and not an output kind, because the contributions stay distinct
  # and keyed by who made them: `cli/src/host/state.rs` keys a service's state
  # directory by the name it arrives under, and two call sites look up
  # `registry`, `dns` and `proxy` by literal string. A collection is keyed by
  # contributor, which is exactly that name — so `lab-services` folds these
  # without the fold being written anywhere outside a floe.
  #
  # It was `catallaxy.hostService`, an output kind, which made the fan-in the
  # container's job: `modules/lab/host/default.nix` read every emitter off the
  # link because nothing else could. An output kind is the right channel when
  # the contributions *merge* — `catallaxy.component` is the case — and the
  # wrong one when they stay apart.
  # Which container on the lab's network answers for the lab's names.
  #
  # Narrower than `HOST_SERVICE` on purpose, and a different question: that one
  # is "start this", collected by `lab-services`, and this one is "resolve
  # through this", read by the one floe that needs it. A reader cannot get this
  # from the collection — a `collects` is the collector's, and a peer asking
  # "is there a resolver, and what is it called" is asking for exactly one
  # answer or none.
  #
  # It was `lab.egress.resolvers`, which the lab filled by reading
  # `lab.dns.enable` and `lab.dns.containerName` — one floe's configuration
  # read out of another's options by the thing holding both.
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

  # Every hostname a cluster serves that the lab is the edge for.
  #
  # Exported by a cluster the lab fronts, and *not* exported by one that is its
  # own edge — which is the whole of how that is said now. A lab has nothing to
  # answer for a cluster it does not front, so the boundary stays shut rather
  # than carrying a mode for a reader to filter on.
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

  # What crosses a cluster boundary, for the one signature where that is not
  # all of it. Same `name` as the full one deliberately: resolution keys on the
  # name, so a consumer of `mesh` resolves against whichever provider its own
  # cluster has — the real netbird next door, or this, re-exported from the
  # cluster running it. The compatibility check then decides whether that
  # consumer's fields are available where it was placed, naming the field if
  # they are not.
  #
  # This is what `T.local` was for. A local field used to become a `throw` when
  # the value crossed, so a consumer reading it found out at read time; now the
  # boundary carries a signature that simply does not promise it, and the
  # refusal is at link with the field named. `namespace` and
  # `managementInternalUrl` are the two that stay behind: one names an object
  # in one cluster, the other an address only reachable inside it.
  # What crosses of `X509_ISSUANCE`: whether a browser will trust what this
  # signs, which is true anywhere, and not `issuerRef` or `caSecret`. Those
  # name a ClusterIssuer object and a Secret in one cluster, so a Certificate
  # elsewhere naming either stays pending forever against something that does
  # not exist there.
  # What a cluster that does not run the mesh may read of it: where to reach
  # the control plane, and where a human finds its dashboard. Not `namespace`
  # or `managementInternalUrl` — one is a position in the cluster running it
  # and the other an address only reachable from inside it.
  #
  # A projection of the signature above rather than a second signature beside
  # it. It used to be written out and joined to the full form by a `crossable`
  # table, which is one fact in three places and the only thing checking that
  # the narrow form had not drifted into promising more. `floe.project` makes
  # `narrows` hold by construction, and an allowlist means a field added above
  # stays inside until someone says otherwise.
  #
  # `behaviour` does not travel — core's `mkSig` pattern is closed and the
  # prelude's wrapper is not in the path — which is the answer the hand-written
  # form reached too, with `behaviour = [ ]` and a comment saying a narrowing
  # promises less, including less behaviour. The obligation belongs to whoever
  # runs the mesh and is discharged in that cluster's own link.
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

  # A retrieval signature: where a deferred value will be readable, not what it
  # is. One resource's declared output, read by another in the same lab — the
  # renderer turns it into a local interpolation inside one state file or a
  # remote-state read across two, and which of those it is depends on where the
  # resources landed rather than on anything the floe said.
  #
  # This replaces a bare label path, `mkDeferred [ "identity" "result" ]`,
  # which told the renderer nothing it could check. The fields do the checking
  # at the point the token is minted, so the renderer no longer counts the
  # parts of a path and explains that it wanted two.
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
