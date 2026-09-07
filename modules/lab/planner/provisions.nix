# Steps for a cluster another cluster brings into existence.
#
# This is the answer to RFC 0005 §7 open question 1, and the previous
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
# a constraint. RFC 0003 §6 names this exactly: an accident that happens to
# be correct is not an ordering constraint.
#
# So the edge constrains apply order. A provisioned cluster follows the
# management cluster's *deploy*, not merely its creation: the CR that brings
# it into existence is in those manifests, so before they are applied there
# is nothing for a controller to reconcile.
{
  lib,
  config,
  t,
  needs,
  wants,
  stackNames,
}:

let
  clusters = config.lab.clusters;

  # `(management cluster, provisioned cluster, declaration)`, flattened once.
  edges = lib.concatLists (
    lib.mapAttrsToList (
      mgmt: c: lib.mapAttrsToList (provisioned: p: { inherit mgmt provisioned p; }) c.provisions
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
  # All three are silent at runtime. The first leaves a step addressing a
  # cluster the lab has no kubecontext for; the second has two things creating
  # one cluster and neither knowing; the third produces a cluster twice.
  assertions =
    map (e: {
      assertion = clusters ? ${e.provisioned};
      message =
        "cluster '${e.mgmt}' provisions '${e.provisioned}', which this lab does not declare. "
        + "A provisioned cluster is an ordinary `lab.clusters` entry — it is what the lab "
        + "installs into once it exists.";
    }) edges
    ++ map (e: {
      assertion =
        !(clusters ? ${e.provisioned}) || clusters.${e.provisioned}.spec.provisioner == "external";
      message =
        "cluster '${e.mgmt}' provisions '${e.provisioned}', and '${e.provisioned}' is "
        + "provisioned by ${clusters.${e.provisioned}.spec.provisioner or "?"} as well. Two things "
        + "creating one cluster is two clusters and one name; use `floes.external-cluster` for a "
        + "cluster something else brings into existence.";
    }) edges
    ++ lib.mapAttrsToList (name: n: {
      assertion = n < 2;
      message =
        "cluster '${name}' is provisioned by ${toString n} clusters "
        + "(${
          lib.concatMapStringsSep ", " (e: "'${e.mgmt}'") (lib.filter (e: e.provisioned == name) edges)
        }).";
    }) (lib.zipAttrsWith (_: v: lib.length v) (map (e: { ${e.provisioned} = 1; }) edges));

  # A cluster the lab installs into has to become reachable somehow. Two ways,
  # one per camp, and a cluster that names neither fails at its first kubectl
  # call with a context that does not exist — after the plan has already
  # created things.
  externalClusters = lib.filterAttrs (_: c: c.spec.provisioner == "external") clusters;

  kubeconfigFromOf =
    c: (lib.head (lib.attrValues c.out.cluster)).config.external.kubeconfigFrom or null;

  unreachable = lib.mapAttrsToList (name: c: {
    assertion = provisionerOf name != null || kubeconfigFromOf c != null;
    message =
      "cluster '${name}' is provisioned externally and nothing says how its kubeconfig "
      + "arrives. Either name it in some cluster's `provisions` (a controller reconciles it, "
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

          # After every apply, because the publication that produces it is
          # part of one. `wants`, since a lab may have stacks that publish
          # nothing and there is then no anchor to need.
          after = map (s: wants "stack/${s}/applied") stackNames;
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

      # Every step here runs kubectl against the *management* cluster: the CR
      # lives there, and the provisioned cluster may not exist yet. The kinds
      # spell this as `target` = the cluster the resource represents and
      # `kubeContext` = the cluster holding it, which are different clusters
      # and were worth getting the right way round.
      onMgmt = clusters.${e.mgmt}.spec.kubeContext;

      resourceParams = {
        target = target;
        kubeContext = onMgmt;
        inherit (e.p) resourceKind resourceName;
      };
    in
    {
      # ---- deploy ----------------------------------------------------------

      # The CR is applied with the management cluster's manifests; this waits
      # for the controller to make it real. It is the step that turns "we
      # asked for a cluster" into "there is one", and it is why everything
      # about the provisioned cluster is ordered after the management
      # cluster's *deploy* rather than merely its creation.
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

      # Read the kubeconfig out of the CR's connection Secret and write it
      # locally under the context the provisioned cluster's floe declared.
      # The cluster is unreachable until this runs.
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

      # ---- teardown --------------------------------------------------------

      # First, while the cluster still exists to run it: deleting its
      # LoadBalancer Services makes the cloud controller release the load
      # balancers it made. Delete the cluster first and they outlive it,
      # billed and with nothing left that knows their name.
      "release-cluster-cloud-resources-${target}" = {
        kind = "release-cluster-cloud-resources";
        description = "Release '${target}' cloud resources before deleting it";
        cluster = target;
        provides = [ (t.cluster target).cloudReleased ];
        params = {
          target = target;
          kubeContext = clusters.${target}.spec.kubeContext;
        };
      };

      # Adopt before deleting. A managed resource that has lost its external
      # name deletes the CR and leaves the cloud object, which is the same
      # class of failure as skipping the release above.
      "reconcile-managed-resource-${target}" = {
        kind = "reconcile-managed-resource";
        description = "Adopt the '${target}' cluster resource on '${e.mgmt}'";
        cluster = e.mgmt;
        provides = [ "cluster/${target}/mr-reconciled" ];
        after = [ (wants (t.cluster target).cloudReleased) ];
        params = resourceParams;
      };

      "delete-managed-resource-${target}" = {
        kind = "delete-managed-resource";
        description = "Delete the '${target}' cluster resource on '${e.mgmt}'";
        cluster = e.mgmt;
        provides = [ (t.cluster target).managedResourceDeleted ];
        after = [ (needs "cluster/${target}/mr-reconciled") ];
        params = resourceParams;
      };

      # The delete returns as soon as the CR is marked; the cluster is gone
      # when the provider says so. Waiting is what makes the management
      # cluster safe to tear down next — destroy it first and the CR goes with
      # it while the cloud cluster keeps running.
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
  inherit provisionerOf;

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
    lib.optional (clusters.${name}.spec.provisioner == "external") (
      needs (t.cluster name).kubeconfigSynced
    );

  # And the teardown side: the management cluster is destroyed after every
  # cluster it provisioned is gone.
  teardownAfterFor =
    name: map (e: wants (t.cluster e.provisioned).gone) (lib.filter (e: e.mgmt == name) edges);
}
