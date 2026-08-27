# The output kinds this distribution registers. Floe core registers none:
# kinds belong to a distribution.
#
# `catallaxy.component` is what every cluster-component floe emits and lives
# in ./component.nix, beside the monoid that joins two of them.
{ lib, floe }:

let
  T = floe.T;

  # Field names track `ClusterSpec` in `cli/src/domain/cluster.rs` so that
  # plugging this into the CLI later is a lowering rather than a translation.
  clusterSchema = T.record {
    name = T.k8sName;
    provisioner = T.enum [
      "k3d"
      "talos"
      "crossplane"
      "external"
    ];
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
    k3d = T.record {
      clusterName = T.str;
      image = T.str;
      ports = T.listOf T.str;
    };
  };

  componentLib = import ./component.nix { inherit lib floe; };
in
componentLib
// {
  cluster = floe.mkOutputKind {
    name = "catallaxy.cluster";
    schema = clusterSchema;
  };
}
