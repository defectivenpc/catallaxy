{
  lib,
  floe,
  k8sApi,
  sigs,
}:

let
  T = floe.T;

  stepType = import ../../eval/step-type.nix {
    inherit lib;
    planTokens = import ../../plan-tokens.nix { inherit lib; };
  };

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

  talosSchema = T.named "talos" (
    T.record {
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
    }
  );

  externalSchema = T.named "externalCluster" (
    T.record {
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
    }
  );

  edgeSchema = T.named "edge" (
    T.record {
      mode = T.enum [
        "proxy"
        "self"
        "none"
      ];

      backend = T.nullOr T.str;

      httpPort = T.port;
      httpsPort = T.port;
    }
  );

  clusterSchema = T.named "clusterDescriptor" (
    T.record {
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
    }
  );

  labStoreRecord = T.named "labStore" (
    T.record (
      removeAttrs sigs.LAB_SECRET_STORE.fields [
        "name"
        "writable"
      ]
      // {
        direction = T.enum [
          "authored"
          "runtime"
        ];
      }
    )
  );

  labSecretRecord = T.named "labSecret" (
    T.record (
      removeAttrs sigs.LAB_SECRET.fields [
        "name"
        "readableKeys"
      ]
    )
  );

  componentLib = import ./component.nix { inherit lib floe k8sApi; };

  resourceLib = import ./resources.nix { inherit lib floe; };
in
componentLib
// {
  inherit gatewayNodePorts;
  inherit (resourceLib) resources publications;

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

  labStores = floe.mkSig {
    name = "catallaxy.labStores";
    canonicalName = "labStores";
    description = "Every store the lab reads authored secret values from, keyed by the name the CLI knows it as.";
    fields = T.attrsOf labStoreRecord;
  };

  labSecrets = floe.mkSig {
    name = "catallaxy.labSecrets";
    canonicalName = "labSecrets";
    description = "Every secret the lab holds, keyed by the name the CLI knows it as.";
    fields = T.attrsOf labSecretRecord;
  };

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

  routedHosts = floe.mkSig {
    name = "catallaxy.routedHosts";
    canonicalName = "routedHosts";
    description = "Hostnames the lab's ingress routes, keyed by the cluster that serves them.";
    fields = T.attrsOf (T.listOf T.dnsName);
  };

  networkPolicy = floe.mkSig {
    name = "catallaxy.networkPolicy";
    canonicalName = "networkPolicy";
    description = "That something in this cluster enforces a NetworkPolicy, and what implements it.";
    fields = {
      implementation = T.str;
    };
  };

  dnsInfo = floe.mkSig {
    name = "catallaxy.dnsInfo";
    canonicalName = "dnsInfo";
    description = "Where the lab's resolver answers, as `cata lab dns` configures the host.";
    fields = T.named "dnsInfo" (
      T.record {
        host = T.str;
        port = T.port;
        zone = T.dnsName;

        tsigKeyname = T.str;
        tsigSecret = T.str;
        tsigSecretAlg = T.str;
      }
    );
  };

  steps = floe.mkSig {
    name = "catallaxy.steps";
    canonicalName = "steps";
    description = "Plan steps a unit of a cluster contributes, keyed by step name.";

    fields = T.attrsOf (T.named "clusterStep" (T.moduleType stepType.declaredStepType));
  };

  labSteps = floe.mkSig {
    name = "catallaxy.labSteps";
    canonicalName = "labSteps";
    description = "Every plan step the lab's floes contribute, keyed by step name.";

    fields = T.attrsOf (T.named "labStep" (T.moduleType stepType.declaredStepType));
  };

  labServices = floe.mkSig {
    name = "catallaxy.labServices";
    canonicalName = "labServices";
    description = "Every host service the lab runs, keyed by the name the CLI knows it as.";
    fields = T.attrsOf (T.named "service" (T.record sigs.HOST_SERVICE.fields));
  };

  cluster = floe.mkSig {
    name = "catallaxy.cluster";
    canonicalName = "clusterDescriptor";
    description = "How a cluster is created and who fronts it — the descriptor `cata` builds it from.";
    fields = clusterSchema;
  };
}
