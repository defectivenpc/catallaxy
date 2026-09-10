# The output kinds this distribution registers. Floe core registers none:
# kinds belong to a distribution.
{ lib, floe }:

let
  T = floe.T;

  k3dSchema = T.record {
    clusterName = T.str;
    image = T.nullOr T.str;
    network = T.nullOr T.str;
    noTraefik = T.bool;
    noServiceLB = T.bool;
    noFlannel = T.bool;
    noLocalStorage = T.bool;
    ports = T.listOf T.str;
    extraApiServerArgs = T.listOf T.str;
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
    provider = T.str;
    kubeContext = T.str;
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

  # RFC 0003's category, registered here beside the reconcile camp's. Both
  # are kinds a floe emits; nothing in core knows either.
  resourceLib = import ./resources.nix { inherit lib floe; };
in
componentLib
// {
  inherit gatewayNodePorts;
  inherit (resourceLib) resources publications;
  resourcePhases = resourceLib.phases;

  cluster = floe.mkOutputKind {
    name = "catallaxy.cluster";
    description = "How a cluster is created and who fronts it — the descriptor `cata` builds it from.";
    schema = clusterSchema;
  };
}
