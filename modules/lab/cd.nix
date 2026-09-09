# How the lab's manifests reach its clusters.
#
# `lab.out.cd` was three hardcoded values in `out.nix` — `kapp`,
# `kubectl-ssa`, no git — which was right while nothing could say otherwise.
# `DELIVERY_POLICY` says otherwise: a floe that installs a CD tool answers
# with the strategy it implements, and the lab reads it rather than being told
# twice.
#
# The steps below are the other half. A gitops lab cannot deploy the ordinary
# way: `cata` applies Argo, publishes the tree Argo reads, and then stops
# applying. Each of those is a step kind the CLI already implements; what was
# missing was anything declaring them.
{
  config,
  lib,
  ...
}:

let
  t = import ../../lib/plan-tokens.nix { inherit lib; };
  inherit (import ../../lib/eval/anchors.nix { }) needs wants;

  clusters = config.lab.clusters;
  clusterNames = lib.attrNames clusters;

  # Every provide of a signature, across every cluster, as
  # `{ cluster; unit; value; }`. The same shape `modules/lab/cluster.nix` uses
  # to find SECRET_STOREs: ask what a floe *promised*, off its definition,
  # rather than guessing from what it rendered.
  providesOf =
    sigName:
    lib.concatLists (
      lib.mapAttrsToList (
        clusterName: cluster:
        lib.concatLists (
          lib.mapAttrsToList (
            unit: inst:
            lib.mapAttrsToList (instName: _: {
              cluster = clusterName;
              inherit unit;
              value = cluster.link.provides.${unit}.${instName};
            }) (lib.filterAttrs (_: sig: sig.name == sigName) inst.def.provides)
          ) cluster.floes
        )
      ) clusters
    );

  policies = providesOf "DELIVERY_POLICY";
  repos = providesOf "GIT_REPOSITORY";

  # A lab-wide decision made per cluster. Two clusters delivering differently
  # is a real thing to want and not a thing `cliConfig.cd` can express — it is
  # one object — so it is refused here rather than silently taking the first.
  distinct = lib.unique (map (p: p.value.strategy) policies);

  policy =
    if policies == [ ] then
      # Nothing said otherwise. `cata` applies, which is what every lab did
      # before a floe could answer.
      {
        strategy = "kapp";
        bootstrap = "kubectl-ssa";
      }
    else
      {
        strategy = (lib.head policies).value.strategy;
        bootstrap = (lib.head policies).value.bootstrapTool;
      };

  gitops = policy.strategy == "argocd";

  # Where the tree is published. `internalUrl`, because the thing that reads
  # it is Argo, inside the cluster — the publish itself runs from the host and
  # goes through the routed name, which is what `externalUrl` is.
  repo = if repos == [ ] then null else (lib.head repos).value;

  # The cluster Argo runs on. Taken from where the DELIVERY_POLICY came from,
  # so a lab does not name it a second time.
  cdCluster = if policies == [ ] then null else (lib.head policies).cluster;

  # The root Application, as a file in the lab package rather than a bundle
  # resource.
  #
  # It cannot be a bundle: bundles are applied at `deploy-manifests`, which
  # runs *before* the tree is published, so an Application pointing at an
  # empty repository would sync nothing and report success. `cata` applies
  # this one by path, last, once there is something for it to point at.
  #
  # An app-of-apps in the plainest form: one Application whose source is the
  # published directory, so everything under it is Argo's from then on.
  rootApplication = lib.optionalAttrs (gitops && repo != null) {
    apiVersion = "argoproj.io/v1alpha1";
    kind = "Application";
    metadata = {
      name = "root";
      namespace = "argocd";
      # Without it, deleting the Application orphans everything it created,
      # and a `lab destroy` that leaves the cluster full is not a destroy.
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
          # Both, deliberately. `prune` off leaves a resource removed from git
          # running forever; `selfHeal` off means a hand edit in the cluster
          # wins over what is committed, which is the opposite of the point.
          prune = true;
          selfHeal = true;
        };
        syncOptions = [ "CreateNamespace=true" ];
      };
    };
  };

  # Every one of these addresses the cluster by context, and none of them can
  # derive it — the plan is what resolves it, and a step that omits it is told
  # so at run time rather than at eval. `deploy-manifests` has always passed
  # it; these four were written without it and step 7 failed on the first run.
  kubeContext = if cdCluster == null then null else clusters.${cdCluster}.spec.kubeContext;
in
{
  config.lab.assertions =
    lib.optional (lib.length distinct > 1) {
      assertion = false;
      message =
        "clusters in this lab deliver differently (${lib.concatStringsSep ", " distinct}), and "
        + "`cd` is one object for the whole lab — the CLI has nowhere to put a second strategy";
    }
    ++ lib.optional (gitops && repo == null) {
      assertion = false;
      message =
        "delivery is argocd and nothing in this lab provides GIT_REPOSITORY, so there is nowhere "
        + "to publish the manifests Argo is supposed to read — it would come up with an empty "
        + "repository and report everything as synced";
    };

  options.lab.out.rootApplication = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    readOnly = true;
    description = "The Argo Application `apply-root-application` applies, or `{ }`.";
  };

  options.lab.out.cd = lib.mkOption {
    type = lib.types.attrs;
    internal = true;
    readOnly = true;
    description = "What `cliConfig.cd` is lowered from.";
  };

  config.lab.out.rootApplication = rootApplication;

  config.lab.out.cd = {
    inherit (policy) strategy bootstrap;

    git =
      lib.optionalAttrs (gitops && repo != null) {
        repo = repo.cloneUrl;
        branch = "main";
        path = "manifests";
        provider = "forgejo";
      }
      // lib.optionalAttrs (gitops && repo != null && repo.credentials != null) {
        # `optionalAttrs` on the attribute, not `mkIf` on the value. `lab.out.cd`
        # is `types.attrs`, so nothing processes a `mkIf` inside it — the
        # wrapper reaches the CLI as the value and `lab up` fails parsing the
        # config with "missing field `context`". Same shape as the
        # `optionalAttrs`-on-a-bundle bug in otel-collector.
        credentialFromKubeSecret = {
          context = clusters.${cdCluster}.spec.kubeContext;
          inherit (repo.credentials) namespace name;
          key = repo.credentials.passwordKey;
          inherit (repo.credentials) username;
        };
      };
  };

  # ---- the gitops steps -------------------------------------------------
  #
  # Only when something took delivery over. A kapp lab's `deploy-manifests`
  # step does the whole job and none of these have anything to do.
  config.lab.steps = lib.optionalAttrs (gitops && repo != null) {
    bootstrap-argocd = {
      kind = "bootstrap-argocd-kubectl-ssa";
      description = "Apply Argo CD itself, before it can apply anything else";
      cluster = cdCluster;
      provides = [ t.lab.cdBootstrapped ];

      # Something has to apply Argo, and it cannot be Argo.
      after = [ (needs (t.cluster cdCluster).created) ];
      params = {
        target = cdCluster;

        # `bootstrap/`, not `manifests/`. The bootstrap tree is what a
        # server-side apply reads — it carries `.wave-meta` — and it is the
        # only part of the lab `cata` still applies once Argo is running.
        manifestRoot = "bootstrap/${cdCluster}";

        inherit kubeContext;
      };
    };

    bootstrap-repos = {
      kind = "bootstrap-forgejo-repos";
      description = "Create the repository Argo clones from";
      cluster = cdCluster;
      provides = [ t.lab.gitReady ];

      # After the manifests, not just after Argo. The git server is a
      # workload in this cluster, and creating a repository on a Forgejo that
      # is not running yet fails on connection refused — the plan put this
      # before `deploy-manifests` until the dependency was stated.
      after = [
        (needs t.lab.cdBootstrapped)
        (needs (t.cluster cdCluster).deployed)
      ];
      params = {
        target = cdCluster;
        inherit kubeContext;
      };
    };

    publish-manifests = {
      kind = "publish-manifests";
      description = "Push the rendered manifests into the lab's own git server";
      provides = [ t.lab.manifestsPushed ];
      after = [ (needs t.lab.gitReady) ];
    };

    apply-root-application = {
      kind = "apply-root-application";
      description = "Point Argo at the published tree and hand the cluster over";
      cluster = cdCluster;
      provides = [ t.lab.cdHandedOver ];

      # Last. Everything before it exists so that this one has something true
      # to point at: Argo running, a repository, and a tree in it.
      after = [ (needs t.lab.manifestsPushed) ];
      params = {
        target = cdCluster;
        inherit kubeContext;
        manifestPath = "cd/root-application.yaml";
      };
    };
  };
}
