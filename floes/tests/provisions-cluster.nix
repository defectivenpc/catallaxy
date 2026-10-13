# provisions-cluster, alone.
#
# It renders nothing, so the whole of what it says is the answer it gives:
# the coordinates of an object that will become a cluster. What makes that
# worth a floe is the direction — the management cluster holds it and the
# resulting cluster reads it, where a declaration on the lab had the
# management cluster naming a cluster and the planner reading both.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe {
    name = "provisions-cluster";
    inputs = {
      resourceKind = "clusters.kubernetes.digitalocean.crossplane.io";
      resourceName = "workload";
    };
  };
in
lib.runTests {

  # The coordinates, as one value for the resulting cluster to read.
  testItProvidesTheObjectsCoordinates = {
    expr = r.provides.provisioning;
    expected = {
      resourceKind = "clusters.kubernetes.digitalocean.crossplane.io";
      resourceName = "workload";
    };
  };

  # Nothing installs. The object itself is applied with the management
  # cluster's manifests — by a composition, a Cluster API resource, or a
  # `custom` floe holding the YAML — and what this adds is the statement that
  # it becomes a cluster this lab holds.
  testItInstallsNothing = {
    expr = r.link.out ? "catallaxy.component";
    expected = false;
  };

  # It requires no cluster, which is what tells it apart from everything in
  # `floes/components`: it is a statement about a cluster that does not exist
  # yet, held by one that does.
  testItRequiresNothing = {
    expr =
      lib.attrNames
        (import ../provisioners/provisions-cluster.nix {
          inherit lib pkgs;
          catallaxy = support.catallaxy;
          inherit (support.catallaxy) floe sigs kinds;
        }).requires;
    expected = [ ];
  };
}
