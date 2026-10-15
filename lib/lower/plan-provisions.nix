# Steps for a cluster another cluster brings into existence.
#
# This is the answer, and the previous
# implementation is the argument for it. Its `cloud-teardown` plan opened:
#
#   [001] create-cluster create-cluster-adopted   provisioner=crossplane
#   [002] create-cluster create-cluster-workload  provisioner=crossplane
#   [003] deploy-manifests deploy-manifests-adopted
#   ...
#   [007] create-cluster create-cluster-mgmt      provisioner=k3d
#
# The provisioned clusters are "created" before the management cluster that
# creates them exists, and their manifests are deployed before that too. It
# ran, because every one of those steps is a no-op for `crossplane` and the
# deploys were skipped by a policy — but the order was the sort's doing, not
# a constraint. the name for it is exact: an accident that happens to
# be correct is not an ordering constraint.
#
# So the edge constrains apply order. A provisioned cluster follows the
# management cluster's *deploy*, not merely its creation: the CR that brings
# it into existence is in those manifests, so before they are applied there
# is nothing for a controller to reconcile.
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
  # `(management cluster, provisioned cluster, coordinates)`, read off the
  # link rather than off a declaration.
  #
  # The provisioned cluster's *claim* declares an optional
  # `CLUSTER_PROVISIONING` hole — `external-cluster` does, because a cluster
  # something else creates is exactly the external case — and the lab names
  # which cluster fills it. So the management cluster is the *provider* of
  # that hole, which the wiring already says, and the coordinates are the
  # value it provided.
  #
  # Read off the claim and not the cluster, because the hole is the
  # provisioner's and the provisioner is a unit beside the cluster it
  # establishes. It was the cluster's when the two were one unit.
  #
  # It used to be `lab.clusters.<mgmt>.provisions.<provisioned>`: a second
  # place for the CR's name, declared on the management cluster and read by
  # the planner, with three assertions standing in for what a link says by
  # construction. The provisioned cluster could be absent, non-external, or
  # claimed twice; a hole has exactly one provider and only resolves against a
  # cluster in the link.
  edges = lib.concatLists (
    lib.mapAttrsToList (
      provisioned: _:
      let
        wired = link.wiring.optional.${catallaxy.claimUnitFor provisioned}.provisioning or null;
      in
      lib.optional (wired != null) {
        inherit provisioned;

        mgmt = wired.instName;

        p = clusters.${provisioned}.spec.provisioning.config.external.provisionedBy;
      }
    ) clusters
  );

  # Which cluster provisions this one, or null. A cluster provisioned twice is
  # refused below rather than resolved by taking the first.
  provisionerOf =
    name:
    let
      hits = lib.filter (e: e.provisioned == name) edges;
    in
    if hits == [ ] then null else lib.head hits;

  # ---- refusals ----------------------------------------------------------
  #
  # Three went with the declaration, because a link says them by construction:
  # a hole resolves only against a unit of the lab's link, so a management
  # cluster cannot name a cluster the lab does not have; the hole is on
  # `external-cluster`, so nothing else can be the thing created; and a hole
  # has exactly one provider, so two clusters claiming one is the ambiguity
  # error rather than a count.
  assertions = [ ];

  # A cluster the lab installs into has to become reachable somehow. Two ways,
  # one each for bundles and resources, and a cluster that names neither fails at its first kubectl
  # call with a context that does not exist — after the plan has already
  # created things.
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

  # The state-based half of the same job the `provisions` steps do for the
  # reconcile half: put the kubeconfig where kubectl will find it, under the
  # context the lab decided.
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

  # ---- steps -------------------------------------------------------------

  stepsFor =
    e:
    let
      target = e.provisioned;

      onMgmt = clusters.${e.mgmt}.spec.claim.context;

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
          kubeContext = clusters.${target}.spec.claim.context;
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
        params = resourceParams // {
          waitTimeoutSeconds = 1800;
        };
      };
    };
in
{
  inherit ;

  assertions = assertions ++ unreachable;

  steps = lib.foldl' lib.mergeAttrs { } (map stepsFor edges) // kubeconfigSteps;

  # Extra ordering on steps the main planner emits, so a provisioned cluster's
  # own lifecycle waits on the machinery above rather than on nothing.
  #
  # Returned as a function rather than merged here because `create-cluster`
  # and `deploy-manifests` belong to the cluster loop in `plan.nix`; this only
  # says what else they wait for.
  extraAfterFor =
    name:
    lib.optional (variantOf clusters.${name} == "external") (needs (t.cluster name).kubeconfigSynced);

  # And the teardown side: the management cluster is destroyed after every
  # cluster it provisioned is gone.
  teardownAfterFor =
    name: map (e: wants (t.cluster e.provisioned).gone) (lib.filter (e: e.mgmt == name) edges);
}
