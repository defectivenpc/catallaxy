# The output kinds this distribution registers. Floe core registers none:
# kinds belong to a distribution.
#
# `catallaxy.component` is what every cluster-component floe emits and lives
# in ./component.nix, beside the monoid that joins two of them.
{ lib, floe }:

let
  T = floe.T;

  # `K3dConfig` in `cli/src/domain/cluster.rs`, field for field. Only
  # `image` and `network` are `Option` there; every other key is required,
  # so an omitted one is a parse error rather than a default.
  #
  # `network` is `null` here on purpose: which docker network a cluster
  # joins is a lab fact, and the lab fills it in.
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

  # Where a gateway sits when nothing assigns LoadBalancer addresses.
  #
  # Two floes need these numbers and neither can read them off the other: the
  # provisioner answers `edge.httpPort` before any member is linked, and the
  # gateway binds them from inside a cluster it requires. A floe cannot
  # require the thing that requires it.
  #
  # So they are one value in the distribution rather than two defaults that
  # agree by convention. A convention would be a check; this is not
  # checkable-and-wrong, it is single-valued.
  gatewayNodePorts = {
    http = 30080;
    https = 30443;
  };

  # Talos-in-docker. `TalosConfig` in `cli/src/domain/cluster.rs`, field for
  # field, with the same two `Option`s.
  #
  # `reachableFrom` is empty here for the reason `k3d.network` is null:
  # talosctl will not join a network it did not make, so whatever has to
  # reach the cluster joins *its* network instead — and which containers
  # those are is a fact about the lab, not about the cluster.
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

  # A cluster something else brings into existence.
  #
  # `cata` creates nothing for one of these: the `create-cluster` step is a
  # no-op and the cluster arrives because a controller reconciled a CR, or a
  # state-based apply made it, or because it was already there. What makes it
  # a *lab* cluster is that a lab names it and installs into it.
  #
  # `madeBy` is free text and exists for the operator reading a plan. It is
  # not dispatched on — the whole point of this variant is that the lab does
  # not act — and a message saying "created by crossplane on mgmt" is the
  # difference between a no-op step that reads as broken and one that reads
  # as waiting.
  externalSchema = T.record {
    madeBy = T.str;

    # Where its kubeconfig is published, when a state-based apply made it.
    # Null for one a controller reconciles — there the lab reaches the
    # kubeconfig through the management cluster's `provisions` declaration.
    kubeconfigFrom = T.nullOr (
      T.record {
        store = T.str;
        key = T.str;
      }
    );
  };

  # Where this cluster's edge is — RFC 0005 §6.4.
  #
  # Answered by the provisioner because it is a fact about how the cluster
  # was made, not about what is installed in it. The floes declare
  # hostnames; something outside them has to say where traffic for those
  # hostnames goes.
  edgeSchema = T.record {
    # `proxy` — the lab fronts this cluster, at `backend`.
    # `self`  — the cluster is its own edge and the lab routes nothing to it.
    # `none`  — nothing routes to this cluster at all.
    mode = T.enum [
      "proxy"
      "self"
      "none"
    ];

    # Hostname the lab's proxy dials, resolved on the lab's docker network.
    # Null for every mode but `proxy`, where it is required — a cluster the
    # lab fronts and cannot name a backend for would render a route to
    # nothing and time out every request through it.
    backend = T.nullOr T.str;

    # Ports the proxy dials on that backend.
    #
    # Answered by the provisioner because they follow from how the cluster
    # reaches the outside: k3s's ServiceLB binds 80 and 443 on the node, so a
    # k3d cluster answers those. A provisioner with no such mechanism is
    # reached on a NodePort instead, and the number is the provisioner's to
    # know — the lab defaulting to 80 would be right only by coincidence.
    httpPort = T.port;
    httpsPort = T.port;
  };

  # Field names track `ClusterSpec` in `cli/src/domain/cluster.rs` so that
  # plugging this into the CLI later is a lowering rather than a translation.
  #
  # There is no `provisioner` field. It was a `T.enum` beside an untagged
  # `k3d` record, which made "the provisioner is not a closed set" false of
  # the kind while the floe emitting it said otherwise, and let the tag and
  # the block disagree. The tag is now the union's own key, so the lab reads
  # the provisioner off `config` and the two cannot say different things.
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
