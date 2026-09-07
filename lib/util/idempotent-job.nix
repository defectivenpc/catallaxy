# A Job that re-runs when what you asked for changes, and not otherwise.
#
# Kubernetes has no "run this once, unless the thing it does has changed"
# primitive. A Job is immutable, so a re-render either collides with the
# existing one or needs a new name — and naming it after a hash of the
# *declaration* is what makes the name change exactly when the intent does.
#
# The ConfigMap is the other half: it accumulates one key per generation that
# has been applied, so the set of hashes that ever ran is readable from the
# cluster rather than inferred from Job names that something may have pruned.
{ lib }:

let
  inherit (import ../kubernetes/labels.nix { }) catallaxyManaged;
in
rec {

  hashContent = inputs: lib.substring 0 10 (builtins.hashString "sha256" (builtins.toJSON inputs));

  mkIdempotentJob =
    {
      name,
      namespace,
      contentInputs,
      podSpec,

      behaviourVersion ? 1,

      extraLabels ? { },

      argoCDSyncWave ? "10",

      jobAnnotations ? { },
    }:
    let
      # The hash covers what you declared, not how you implemented it.
      # Reformatting the payload's script or bumping its base image is not a
      # change of desired state and must not re-run the Job against a live
      # API; adding a repository to a list is, and does.
      #
      # `behaviourVersion` is the escape hatch for the case declarations
      # cannot express: you changed what the payload *does* without changing
      # anything it was given. Bump it and the Job runs again.
      hash = hashContent {
        inherit contentInputs behaviourVersion;
      };

      # The implementation's own hash, recorded but not acted on. It is what
      # lets a reader, or a check, see that a payload changed while its
      # declared inputs did not — which is either a cosmetic edit or a
      # forgotten `behaviourVersion` bump, and the difference matters.
      implementationHash = hashContent { inherit podSpec; };
      jobName = "${name}-${hash}";
      ownerName = "${name}-runs";

      commonLabels =
        catallaxyManaged
        // {
          "app.kubernetes.io/component" = name;
          "catallaxy.io/idempotent-job" = "true";
        }
        // extraLabels;

      ownerConfigMap = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = ownerName;
          inherit namespace;
          labels = commonLabels;
          annotations = {

            "catallaxy.io/description" = "Owns every generation of the ${name} bootstrap Job.";
          };
        };

        data."${hash}" = "applied";
      };

      job = {
        apiVersion = "batch/v1";
        kind = "Job";
        metadata = {
          name = jobName;
          inherit namespace;
          labels = commonLabels // {
            "catallaxy.io/idempotent-job-hash" = hash;
          };
          annotations = {

            "catallaxy.io/implementation-hash" = implementationHash;

            "argocd.argoproj.io/sync-wave" = argoCDSyncWave;

            "kapp.k14s.io/update-strategy" = "fallback-on-replace";

          }
          // jobAnnotations;

        };
        spec = {

          backoffLimit = 20;
          template = {
            metadata.labels = commonLabels // {
              "catallaxy.io/idempotent-job-hash" = hash;
            };
            spec = podSpec;
          };
        };
      };
    in
    {
      inherit hash;
      name = jobName;

      # Selects this generation and no other. Waiting on
      # `component=<name>` alone also selects every earlier hash, and on the
      # server-side-apply path nothing prunes them, so one failed Job from a
      # previous render makes the wait fail forever.
      selector = "app.kubernetes.io/component=${name},catallaxy.io/idempotent-job-hash=${hash}";

      resources = {

        "${ownerName}" = ownerConfigMap;
        "${jobName}" = job;
      };
    };
}
