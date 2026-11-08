{
  lib,
  floe,
  ...
}:

let
  T = floe.T;

  stepType = (import ../steps { inherit lib; }).types;

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
in
{
  cluster = floe.mkSig {
    name = "catallaxy.cluster";
    canonicalName = "clusterDescriptor";
    description = "How a cluster is created and who fronts it — the descriptor `cata` builds it from.";
    fields = clusterSchema;
  };

  networkPolicy = floe.mkSig {
    name = "catallaxy.networkPolicy";
    canonicalName = "networkPolicy";
    description = "That something in this cluster enforces a NetworkPolicy, and what implements it.";
    fields = {
      implementation = T.str;
    };
  };

  steps = floe.mkSig {
    name = "catallaxy.steps";
    canonicalName = "steps";
    description = "Plan steps a unit of a cluster contributes, keyed by step name.";

    fields = T.attrsOf (T.named "clusterStep" (T.moduleType stepType.declaredStepType));
  };

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
}
