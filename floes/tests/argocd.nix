# argocd, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "argocd";
    inputs.chart = "/dev/null";
  };
  values = r.bundles.argocd.helmCharts.argocd.values;
  repo = r.bundles.argocd.resources.argocd-repo;
in
lib.runTests {

  # The whole reason GIT_REPOSITORY carries two URLs. Argo clones from inside
  # the cluster, so the repository Secret gets the Service address — the
  # routed name is a longer path to the same server and needs the lab's CA.
  testItClonesOverTheInternalUrl = {
    expr = repo.stringData.url;
    expected = support.stubs.gitRepository.value.internalUrl;
  };

  # A Secret with this label is how Argo finds a repository; there is no CRD
  # for one, so a wrong label is a repository Argo never sees.
  testTheRepositoryIsFoundByLabel = {
    expr = repo.metadata.labels."argocd.argoproj.io/secret-type";
    expected = "repository";
  };

  # Nothing here creates the git credentials — the git server does.
  testItNeedsTheGitCredentials = {
    expr = r.bundles.argocd.needsSecrets;
    expected = [ "forgejo/forgejo-admin" ];
  };

  # The chart writes `argocd-redis` from a `post-install` hook, and a hook is
  # not a rendered manifest — it renders zero Jobs here. Four workloads read
  # that Secret, so without this declaration every one of them looks dangling.
  testTheRedisSecretIsDeclaredAsArrivingLater = {
    expr = lib.elem "argocd/argocd-redis" r.bundles.argocd.externalSecrets;
    expected = true;
  };

  # Handing the cluster over is the point: `cata` stops applying and Argo
  # starts. `bootstrapTool` stays, because something has to apply Argo itself
  # and it cannot be Argo.
  testItTakesOverDelivery = {
    expr = r.provides.delivery;
    expected = {
      strategy = "argocd";
      bootstrapTool = "kubectl-ssa";
      appliedByKapp = false;
    };
  };

  # The chart's defaults are an HA topology with a Redis cluster — three more
  # workloads than a lab reconciling one repository needs.
  testItRunsOneOfEach = {
    expr = {
      ha = values.redis-ha.enabled;
      ctrl = values.controller.replicas;
      appsets = values.applicationSet.enabled;
    };
    expected = {
      ha = false;
      ctrl = 1;
      appsets = false;
    };
  };

  # Argo's own OIDC is `dex`, a second identity provider inside a cluster that
  # already has one. It talks to the issuer directly instead.
  testItRunsNoSecondIdentityProvider = {
    expr = values.dex.enabled;
    expected = false;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };
}
