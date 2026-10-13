# The output kinds this distribution registers. Floe core registers none:
# kinds belong to a distribution.
{ lib, floe }:

let
  T = floe.T;

  k3dSchema = T.record {
    clusterName = T.str;
    image = T.nullOr T.str;
    network = T.nullOr T.str;

    nodeConfigFrom = T.nullOr T.str;
    noTraefik = T.bool;
    noServiceLB = T.bool;
    noFlannel = T.bool;
    noLocalStorage = T.bool;
    ports = T.listOf T.str;
    extraApiServerArgs = T.listOf T.str;
    extraK3sArgs = T.listOf (
      T.record {
        arg = T.str;
        scope = T.str;
      }
    );
    extraVolumes = T.listOf (
      T.record {
        hostPath = T.str;
        containerPath = T.str;
      }
    );
    autoDeployManifests = T.listOf (
      T.record {
        name = T.str;
        path = T.str;
      }
    );
  };

  gatewayNodePorts = {
    http = 30080;
    https = 30443;
  };

  talosSchema = T.record {
    clusterName = T.str;
    image = T.nullOr T.str;
    kubernetesVersion = T.nullOr T.str;
    subnet = T.str;
    exposedPorts = T.listOf T.str;
    mounts = T.listOf T.str;
    memory = T.str;
    cpus = T.str;
    configPatches = T.listOf T.str;
    reachableFrom = T.listOf T.str;
  };

  externalSchema = T.record {
    madeBy = T.str;

    provisionedBy = T.nullOr (
      T.record {
        resourceKind = T.str;
        resourceName = T.k8sName;
      }
    );

    kubeconfigFrom = T.nullOr (
      T.record {
        store = T.str;
        key = T.str;
      }
    );
  };

  edgeSchema = T.record {
    mode = T.enum [
      "proxy"
      "self"
      "none"
    ];

    backend = T.nullOr T.str;

    httpPort = T.port;
    httpsPort = T.port;
  };

  clusterSchema = T.record {
    name = T.k8sName;

    instanceName = T.str;

    kubeContext = T.str;

    wait = T.str;
    kubernetes = T.record {
      distribution = T.str;
      version = T.str;
      controlPlanes = T.int;
      workers = T.int;
    };
    network = T.record {
      podSubnet = T.str;
      serviceSubnet = T.str;
    };
    edge = edgeSchema;
    config = T.taggedUnion {
      k3d = k3dSchema;
      talos = talosSchema;
      external = externalSchema;
    };
  };

  componentLib = import ./component.nix { inherit lib floe; };

  # the resources category, registered here beside the bundle one. Both
  # are kinds a floe emits; nothing in core knows either.
  resourceLib = import ./resources.nix { inherit lib floe; };
in
componentLib
// {
  inherit gatewayNodePorts;
  inherit (resourceLib) resources publications;
  resourcePhases = resourceLib.phases;

  # `clusterDescriptor`, not `cluster`: `KUBERNETES_CLUSTER` is canonically
  # `cluster` — the cluster a member installs into — and a name may not mean
  # two signatures. This one is the descriptor `cata` builds a cluster *from*,
  # which is a different thing wearing the same word.
  # Lab-held material a cluster asks for, keyed by the Secret it lands as.
  #
  # The attribute name *is* the Secret's name: `cata` renders `metadata.name`
  # from it, so a separate field for it would be one the CLI ignores. It was
  # `lab.clusters.<c>.secrets.project`, which made it the last thing a lab
  # handed a cluster — the elaborator took it as a parameter and synthesised a
  # bundle per entry on the cluster's behalf.
  projections = floe.mkSig {
    name = "catallaxy.projections";
    canonicalName = "projections";
    description = "Secrets a cluster asks `cata` to fill from a lab store.";
    fields = T.attrsOf (
      T.record {
        source = T.str;
        namespace = T.k8sName;
        keys = T.attrsOf (
          T.record {
            from = T.str;
            transform = T.nullOr T.str;
            jsonKey = T.nullOr T.str;
          }
        );
      }
    );
  };

  # Every store the lab holds, keyed by the name `cata secrets edit <store>`
  # takes, and every secret, keyed by the name it is edited under.
  #
  # `lab-secrets`' two emissions, and the only thing about the lab's authored
  # material that leaves the lab. `SecretStoreSpec` and `ManagedSecretSpec` in
  # `cli/src/domain/secrets.rs`; the per-record shape is checked where each
  # floe provides `LAB_SECRET_STORE` or `LAB_SECRET`, so these are loose maps
  # the collection already keyed.
  #
  # Those keys are a CLI contract rather than labels, the same way a host
  # service's name is — and `resolve_store_or_path` additionally reads any
  # store argument containing `.` or `/` as a filesystem path.
  labStores = floe.mkSig {
    name = "catallaxy.labStores";
    canonicalName = "labStores";
    description = "Every store the lab reads authored secret values from, keyed by the name the CLI knows it as.";
    fields = T.attrsOf (T.attrsOf T.any);
  };

  labSecrets = floe.mkSig {
    name = "catallaxy.labSecrets";
    canonicalName = "labSecrets";
    description = "Every secret the lab holds, keyed by the name the CLI knows it as.";
    fields = T.attrsOf (T.attrsOf T.any);
  };

  # How the lab's manifests reach its clusters, as a floe's output.
  #
  # `CdConfig` in `cli/src/domain/lab.rs`, plus the root Application that
  # cannot be a bundle resource: bundles are applied at `deploy-manifests`,
  # which runs *before* the tree is published, so an Application pointing at
  # an empty repository would sync nothing and report success. `cata` applies
  # that one by path, last, once there is something true for it to point at.
  #
  # One per lab. Which applier each cluster uses is the cluster's answer and
  # `policies.oneDelivery` refuses a second; what is lab-wide is the
  # *arrangement* — the repository Argo reads and the cluster it runs on —
  # which is a different statement with one answer.
  # `cd`, not `delivery`: that is `DELIVERY_POLICY`'s canonical name — the
  # applier one cluster uses — and a name may not mean two signatures. Same
  # split as `clusterDescriptor` against `cluster`.
  cd = floe.mkSig {
    name = "catallaxy.cd";
    canonicalName = "cd";
    description = "How the lab's manifests reach its clusters, and the root Application that hands one over.";
    fields = T.record {
      bootstrap = T.str;
      git = T.attrsOf T.any;
      rootApplication = T.attrsOf T.any;

      perCluster = T.attrsOf (
        T.record {
          strategy = T.str;
          waitTimeout = T.str;
        }
      );
    };
  };

  # Every hostname the lab's ingress answers for, keyed by the cluster its
  # backend points at.
  #
  # The ingress's own account of what it routes, emitted beside the
  # configuration it routes with — so the document `cata lab verify` probes
  # against and the `use_backend` lines it probes through are one expression.
  # `modules/lab/out.nix` built this by reading every cluster's exported
  # exposure, which answered a different question: a lab with routed
  # workloads and no ingress listed hostnames nothing answered for, and
  # `verify` then refused the lab for publishing no ingress port.
  routedHosts = floe.mkSig {
    name = "catallaxy.routedHosts";
    canonicalName = "routedHosts";
    description = "Hostnames the lab's ingress routes, keyed by the cluster that serves them.";
    fields = T.attrsOf (T.listOf T.dnsName);
  };

  # What `cata lab dns` needs to point the host resolver at the lab.
  #
  # The resolver's own account of itself. It was `lab.dns.out.dnsInfo`, built
  # in the option tree from six `lab.dns.*` options and explicitly null when
  # the lab ran no server — a case the option had to carry in its value
  # because a read-only option counts its default as a definition. A floe
  # that is not placed emits nothing, so the absent case needs no encoding.
  dnsInfo = floe.mkSig {
    name = "catallaxy.dnsInfo";
    canonicalName = "dnsInfo";
    description = "Where the lab's resolver answers, as `cata lab dns` configures the host.";
    fields = T.attrsOf T.any;
  };

  # Every plan step the lab's floes contribute, keyed by step name.
  #
  # `lab-steps`' emission: the fold over every `LAB_STEPS`, with each floe's
  # cluster conditions already expanded into one anchor per cluster. The names
  # are distinct because a floe qualifies its own — two floes emitting
  # `cert-generate` would be two things claiming to mint one CA, which is a
  # collision worth having rather than one to paper over.
  labSteps = floe.mkSig {
    name = "catallaxy.labSteps";
    canonicalName = "labSteps";
    description = "Every plan step the lab's floes contribute, keyed by step name.";
    fields = T.attrsOf (T.attrsOf T.any);
  };

  # Every container the lab runs on the operator's machine, keyed by the name
  # the CLI knows it as.
  #
  # `lab-services`' emission, and the only thing about the host services that
  # leaves the lab. The per-service shape is `HOST_SERVICE`, checked where each
  # floe provides it; this is loose because it is a map the collection already
  # keyed.
  #
  # Those keys are a CLI contract rather than labels: `cli/src/host/state.rs`
  # keys state directories by them, and `create_cluster.rs` finds
  # `registries.yaml` under `registry` while `import_lab_ca` is gated on
  # `proxy` existing.
  labServices = floe.mkSig {
    name = "catallaxy.labServices";
    canonicalName = "labServices";
    description = "Every host service the lab runs, keyed by the name the CLI knows it as.";
    fields = T.attrsOf (T.attrsOf T.any);
  };

  cluster = floe.mkSig {
    name = "catallaxy.cluster";
    canonicalName = "clusterDescriptor";
    description = "How a cluster is created and who fronts it — the descriptor `cata` builds it from.";
    fields = clusterSchema;
  };
}
