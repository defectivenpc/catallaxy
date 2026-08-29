# The deployment and teardown plans, written out rather than derived.
#
# The parked system had a planner: 34 step kinds, an anchor grammar, and a
# topological sort over published tokens. That machinery earns its place when
# floes contribute steps and the order between them is not obvious. Nothing
# contributes steps yet, and three of them in a fixed order is not a graph
# problem, so this is a list.
#
# When a floe needs to contribute a step, this is where the planner goes.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  clusters = config.lab.clusters;

  # `origin`, `description` and `cluster` are all optional on the wire;
  # `policy.retry` is the only required policy field. The retry class is the
  # step kind's, not the author's: `create-cluster` is `oneShot` because
  # running it twice is not the same as running it once.
  step =
    {
      name,
      kind,
      retry,
      description,
      cluster ? null,
      params ? { },
    }:
    {
      inherit
        name
        kind
        description
        params
        ;
      cluster = cluster;
      origin = "lab.plan";
      policy.retry = retry;
    };
in
{
  options.lab.out.deploymentPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab up` executes.";
  };

  options.lab.out.teardownPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab destroy` executes.";
  };

  config.lab.out.deploymentPlan = [
    (step {
      name = "docker-network-create";
      kind = "docker-network-create";
      retry = "idempotent";
      description = "Create docker network '${config.lab.name}'";
      params = {
        name = config.lab.name;
        subnet = config.lab.network.subnet;
        inherit (config.lab.network) gateway;
      };
    })
  ]
  ++ lib.concatLists (
    lib.mapAttrsToList (name: c: [
      (step {
        name = "create-cluster-${name}";
        kind = "create-cluster";
        retry = "oneShot";
        description = "Create ${c.spec.provisioner} cluster '${name}'";
        cluster = name;
        params = {
          inherit name;
          inherit (c.spec) provisioner;
        };
      })
      (step {
        name = "deploy-manifests-${name}";
        kind = "deploy-manifests";
        retry = "idempotent";
        description = "Deploy manifests to '${name}'";
        cluster = name;
        params = {
          target = name;
          bootstrap = false;
          inherit (c.spec) kubeContext;
        };
      })
    ]) clusters
  );

  config.lab.out.teardownPlan =
    lib.mapAttrsToList (
      name: c:
      step {
        name = "destroy-cluster-${name}";
        kind = "destroy-cluster";
        retry = "destructive";
        description = "Destroy ${c.spec.provisioner} cluster '${name}'";
        cluster = name;
        params = {
          inherit name;
          inherit (c.spec) provisioner;
          skipIfMissing = true;
        };
      }
    ) clusters
    ++ [
      (step {
        name = "remove-network";
        kind = "remove-network";
        retry = "destructive";
        description = "Remove docker network '${config.lab.name}'";
      })
    ];
}
