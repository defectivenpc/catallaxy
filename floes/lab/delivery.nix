# How the lab's manifests reach its clusters.
#
# A collector over two signatures, and the clearest case for being one: which
# applier a cluster uses is that cluster's answer, and `policies.oneDelivery`
# refuses a second — but the *arrangement* is lab-wide. Which cluster Argo
# runs on, which repository it reads, and what has to be applied before it can
# apply anything are one statement with one answer, folded from what the
# clusters said.
#
# It was `modules/lab/cd.nix`, which walked every cluster's exports by
# signature name and read `clusters.<c>.spec.claim.context` off the lowered
# spec. The walk is what `collects` is; the context now travels on
# `DELIVERY_POLICY`, because a unit of the link cannot see the lowering of the
# link it is in.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens needs;
in
floe.mkFloe {
  name = "lab-delivery";
  summary = "Folds what each cluster said about applying into one arrangement for the lab.";

  # One arrangement, so one of these.
  singleton = true;

  collects = {
    policy = sigs.DELIVERY_POLICY;

    repo = sigs.GIT_REPOSITORY;
  };

  out.cd = kinds.cd;
  provides.step = sigs.LAB_STEPS;

  body =
    { collects, ... }:
    let
      gitops = lib.filterAttrs (_: p: p.strategy == "argocd") collects.policy;

      anyPolicy = lib.attrValues collects.policy;
      chosen = if gitops != { } then lib.head (lib.attrValues gitops) else null;

      bootstrap =
        if chosen != null then
          chosen.bootstrapTool
        else if anyPolicy == [ ] then
          "kubectl-ssa"
        else
          (lib.head anyPolicy).bootstrapTool;

      cdCluster = if gitops == { } then null else lib.head (lib.attrNames gitops);

      repos = lib.attrValues collects.repo;
      repo = if repos == [ ] then null else lib.head repos;

      handedOver = cdCluster != null && repo != null;

      refusals =
        lib.optional (lib.length (lib.attrNames gitops) > 1) (
          "${toString (lib.length (lib.attrNames gitops))} clusters in this lab run their own "
          + "Argo CD (${lib.concatStringsSep ", " (lib.attrNames gitops)}), and the lab publishes "
          + "one tree for one of them to read. Two is a shape nobody has run."
        )
        ++ lib.optional (cdCluster != null && repo == null) (
          "delivery is argocd and nothing in this lab provides GIT_REPOSITORY, so there is "
          + "nowhere to publish the manifests Argo is supposed to read — it would come up with "
          + "an empty repository and report everything as synced."
        );

      refuse = lib.throwIf (refusals != [ ]) ("lab-delivery: " + lib.concatStringsSep " " refusals);
    in
    {
      out.cd = refuse {
        inherit bootstrap;

        perCluster = lib.mapAttrs (_: p: { inherit (p) strategy waitTimeout; }) collects.policy;

        git =
          lib.optionalAttrs handedOver {
            repo = repo.cloneUrl;
            branch = "main";
            path = "manifests";
            provider = "forgejo";
          }
          // lib.optionalAttrs (handedOver && repo.credentials != null) {
            credentialFromKubeSecret = {
              context = chosen.context;
              inherit (repo.credentials) namespace name;
              key = repo.credentials.passwordKey;
              inherit (repo.credentials) username;
            };
          };

        rootApplication = lib.optionalAttrs handedOver {
          apiVersion = "argoproj.io/v1alpha1";
          kind = "Application";
          metadata = {
            name = "root";
            namespace = "argocd";
            finalizers = [ "resources-finalizer.argocd.argoproj.io" ];
          };
          spec = {
            project = "default";
            source = {
              repoURL = lib.replaceStrings [ repo.externalUrl ] [ repo.internalUrl ] repo.cloneUrl;
              targetRevision = "main";
              path = "manifests/${cdCluster}";
              directory.recurse = true;
            };
            destination = {
              server = "https://kubernetes.default.svc";
              namespace = "default";
            };
            syncPolicy = {
              automated = {
                prune = true;
                selfHeal = true;
              };
              syncOptions = [ "CreateNamespace=true" ];
            };
          };
        };
      };

      provides.step.steps = lib.optionalAttrs handedOver {
        bootstrap-argocd = {
          kind = "bootstrap-argocd-kubectl-ssa";
          description = "Apply Argo CD itself, before it can apply anything else";
          cluster = cdCluster;
          provides = [ planTokens.lab.cdBootstrapped ];

          after = [ (needs (planTokens.cluster cdCluster).created) ];
          params = {
            target = cdCluster;

            manifestRoot = "bootstrap/${cdCluster}";

            kubeContext = chosen.context;
          };
        };

        bootstrap-repos = {
          kind = "bootstrap-forgejo-repos";
          description = "Create the repository Argo clones from";
          cluster = cdCluster;
          provides = [ planTokens.lab.gitReady ];

          after = [
            (needs planTokens.lab.cdBootstrapped)
            (needs (planTokens.cluster cdCluster).deployed)
          ];
          params = {
            target = cdCluster;
            kubeContext = chosen.context;
          };
        };

        publish-manifests = {
          kind = "publish-manifests";
          description = "Push the rendered manifests into the lab's own git server";
          provides = [ planTokens.lab.manifestsPushed ];
          after = [ (needs planTokens.lab.gitReady) ];
        };

        apply-root-application = {
          kind = "apply-root-application";
          description = "Point Argo at the published tree and hand the cluster over";
          cluster = cdCluster;
          provides = [ planTokens.lab.cdHandedOver ];

          after = [ (needs planTokens.lab.manifestsPushed) ];
          params = {
            target = cdCluster;
            kubeContext = chosen.context;
            manifestPath = "cd/root-application.yaml";
          };
        };
      };
    };
}
