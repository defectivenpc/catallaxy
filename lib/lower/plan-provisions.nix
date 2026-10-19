{
  lib,
  catallaxy,
  t,
  needs,
  wants,
  variantOf,
  clusters,
  link,
  stackNames,
}:

let
  edges = lib.concatLists (
    lib.mapAttrsToList (
      provisioned: _:
      let
        wired = link.wiring.optional.${catallaxy.provisionerUnitFor provisioned}.provisioning or null;
      in
      lib.optional (wired != null) {
        inherit provisioned;

        mgmt = wired.instName;

        p = (lib.head (lib.attrValues clusters.${provisioned}.out.cluster)).config.external.provisionedBy;
      }
    ) clusters
  );

  provisionerOf =
    name:
    let
      hits = lib.filter (e: e.provisioned == name) edges;
    in
    if hits == [ ] then null else lib.head hits;

  assertions = [ ];

  externalClusters = lib.filterAttrs (_: c: variantOf c == "external") clusters;

  kubeconfigFromOf =
    c: (lib.head (lib.attrValues c.out.cluster)).config.external.kubeconfigFrom or null;

  unreachable = lib.mapAttrsToList (name: c: {
    assertion = provisionerOf name != null || kubeconfigFromOf c != null;
    message =
      "cluster '${name}' is provisioned externally and nothing says how its kubeconfig "
      + "arrives. Either name the cluster whose `provisions-cluster` floe holds its "
      + "coordinates, with `lab.defaults.CLUSTER_PROVISIONING` (a controller reconciles it, "
      + "and the kubeconfig is in a connection Secret), or set `kubeconfigFrom` on the "
      + "`external-cluster` floe (a state-based apply published it into a store). Without "
      + "one of those every step addressing '${name}' runs against a context nothing wrote.";
  }) externalClusters;

  kubeconfigSteps = lib.foldl' lib.mergeAttrs { } (
    lib.mapAttrsToList (
      name: c:
      let
        from = kubeconfigFromOf c;
      in
      lib.optionalAttrs (from != null) {
        "sync-kubeconfig-${name}" = {
          kind = "sync-kubeconfig";
          description = "Write '${name}' kubeconfig from store '${from.store}'";
          provides = [ (t.cluster name).kubeconfigSynced ];

          after = map (s: wants (t.stack s).applied) stackNames;
          params = {
            target = name;
            clusters = [ name ];
            fromSecret = {
              inherit (from) store key;
            };
          };
        };
      }
    ) externalClusters
  );

  stepsFor =
    e:
    let
      target = e.provisioned;

      onMgmt = clusters.${e.mgmt}.spec.clusterHandle.context;

      resourceParams = {
        target = target;
        kubeContext = onMgmt;
        inherit (e.p) resourceKind resourceName;
      };
    in
    {

      "wait-for-cluster-${target}" = {
        kind = "wait-for-resources";
        description = "Wait for '${e.mgmt}' to reconcile cluster '${target}'";
        cluster = e.mgmt;
        provides = [ (t.cluster target).managedResourceAdopted ];
        after = [ (needs (t.cluster e.mgmt).deployed) ];
        params = {
          target = e.mgmt;
          kubeContext = onMgmt;
          resources = [
            {
              kind = e.p.resourceKind;
              name = e.p.resourceName;
            }
          ];
          waitTimeoutSeconds = 1800;
        };
      };

      "sync-kubeconfig-${target}" = {
        kind = "sync-kubeconfig";
        description = "Fetch '${target}' kubeconfig from '${e.mgmt}'";
        cluster = e.mgmt;
        provides = [ (t.cluster target).kubeconfigSynced ];
        after = [ (needs (t.cluster target).managedResourceAdopted) ];
        params = {
          target = e.mgmt;
          clusters = [ target ];
          kubeContext = onMgmt;
        };
      };

      "release-cluster-cloud-resources-${target}" = {
        kind = "release-cluster-cloud-resources";
        description = "Release '${target}' cloud resources before deleting it";
        cluster = target;
        provides = [ (t.cluster target).cloudReleased ];
        params = {
          target = target;
          kubeContext = clusters.${target}.spec.clusterHandle.context;
        };
      };

      "reconcile-managed-resource-${target}" = {
        kind = "reconcile-managed-resource";
        description = "Adopt the '${target}' cluster resource on '${e.mgmt}'";
        cluster = e.mgmt;
        provides = [ (t.cluster target).managedResourceReconciled ];
        after = [ (wants (t.cluster target).cloudReleased) ];
        params = resourceParams;
      };

      "delete-managed-resource-${target}" = {
        kind = "delete-managed-resource";
        description = "Delete the '${target}' cluster resource on '${e.mgmt}'";
        cluster = e.mgmt;
        provides = [ (t.cluster target).managedResourceDeleted ];
        after = [ (needs (t.cluster target).managedResourceReconciled) ];
        params = resourceParams;
      };

      "wait-for-cluster-gone-${target}" = {
        kind = "wait-for-cluster-gone";
        description = "Wait for '${target}' to be gone";
        cluster = e.mgmt;
        provides = [ (t.cluster target).gone ];
        after = [ (needs (t.cluster target).managedResourceDeleted) ];

        before = [ (wants (t.cluster e.mgmt).destroyed) ];
        params = resourceParams // {
          waitTimeoutSeconds = 1800;
        };
      };
    };
in
{
  assertions = assertions ++ unreachable;

  steps = lib.foldl' lib.mergeAttrs { } (map stepsFor edges) // kubeconfigSteps;

}
