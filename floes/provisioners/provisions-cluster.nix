# This cluster brings another one into existence.
#
# The other side of a provisioner. `k3d-cluster` and friends answer
# `KUBERNETES_CLUSTER` — *I am a cluster* — and this answers
# `CLUSTER_PROVISIONING`: *something here reconciles into one*. It is placed
# in the management cluster, and the cluster that results reads it.
#
# That direction is the whole point. A cluster naming what creates it would be
# a container's provisions depending on its contents; and the coordinates
# belong in one place rather than two that can disagree, which is why the
# resulting cluster reads them rather than restating them.
#
# It renders nothing. The object itself is applied with the management
# cluster's manifests — by a Crossplane composition, a Cluster API resource,
# or a `custom` floe holding the YAML — and what this adds is the statement
# that it will become a cluster this lab holds.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "provisions-cluster";
  summary = "Declares that an object in this cluster reconciles into another cluster.";

  inputs = {
    resourceKind = lib.mkOption {
      type = lib.types.str;
      example = "clusters.kubernetes.digitalocean.crossplane.io";
      description = ''
        Fully qualified kind of the object that represents the cluster.
        Required.

        Qualified because the planner hands it to `kubectl`, and a bare kind
        is ambiguous the moment two API groups define one.
      '';
    };

    resourceName = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of that object. Required.

        A floe rendering the object from this declaration would use the same
        name, which is the point of there being one declaration.
      '';
    };
  };

  provides.provisioning = sigs.CLUSTER_PROVISIONING;

  body =
    { inputs, ... }:
    {
      provides.provisioning = {
        inherit (inputs) resourceKind resourceName;
      };
    };
}
