# velero, alone.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe {
    name = "velero";
    inputs = {
      chart = "/dev/null";
      crds = "/dev/null";
      schedules.daily.schedule = "0 2 * * *";
    };
  };

  values = r.bundles.velero.helmCharts.velero.values;
  location = lib.head values.configuration.backupStorageLocation;
in
lib.runTests {
  # Off the signature, not from a sibling floe's exports with a hardcoded
  # fallback beside it — a default that silently works until the store moves.
  testTheEndpointComesFromTheSignature = {
    expr = location.config.s3Url;
    expected = support.stubs.objectStore.value.s3Endpoint;
  };

  # A self-hosted store has no per-bucket DNS, so the bucket has to be a path
  # segment rather than a subdomain.
  testItAddressesTheBucketByPath = {
    expr = location.config.s3ForcePathStyle;
    expected = "true";
  };

  # The bundle owns them, so the chart's upgrade hook must not also apply
  # them — it re-applies on every upgrade.
  #
  # `installCRDs` was asserted here as well, against a value this chart does
  # not have. The arrangement was never wrong — `helm template` does not render
  # `crds/`, so the bundle is the only thing applying them — but the assertion
  # was checking that a floe asks for something, not that it takes effect.
  testTheChartDoesNotUpgradeTheCrds = {
    expr = values.upgradeCRDs;
    expected = false;
  };

  # Snapshots need a CSI driver that supports them and a filesystem backup
  # needs an agent on every node. Both are decisions, not inherited defaults.
  testItInheritsNoOptionalWorkloads = {
    expr = [
      values.snapshotsEnabled
      values.deployNodeAgent
    ];
    expected = [
      false
      false
    ];
  };

  testSchedulesBecomeVeleroResources = {
    expr = r.bundles.velero.resources.schedule-daily.spec.schedule;
    expected = "0 2 * * *";
  };

  # kube-system holds the control plane and velero's namespace holds the thing
  # taking the backup; restoring either over a live cluster is not a restore.
  testABackupExcludesTheClusterAndItself = {
    expr = r.bundles.velero.resources.schedule-daily.spec.template.excludedNamespaces;
    expected = [
      "kube-system"
      "velero"
    ];
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

}
