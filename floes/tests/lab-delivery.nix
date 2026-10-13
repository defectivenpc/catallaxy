# lab-delivery, alone.
#
# The clearest collector in the set: which applier a cluster uses is that
# cluster's answer, and the *arrangement* — which cluster Argo runs on, which
# repository it reads, what has to be applied before it can apply — is one
# statement folded from what the clusters said.
#
# So the cases are about the fold. A kapp lab hands nothing over; a gitops lab
# hands over to the cluster that said it runs Argo and no other; and the two
# ways a lab can be incoherent are refused rather than rendered.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  deliveryWith =
    without:
    support.evalFloe {
      name = "lab-delivery";
      inherit without;
    };

  gitopsWith =
    stubValues:
    support.evalFloe {
      name = "lab-delivery";
      stubValues = {
        delivery.strategy = "argocd";
      }
      // stubValues;
    };

  cdOf = r: r.link.out."catallaxy.cd".lab-delivery;
  stepsOf = r: r.link.provides.lab-delivery.step.steps;

  # The stub answers `kapp`, which is the lab nothing took delivery over.
  kappLab = deliveryWith [ ];
in
lib.runTests {

  # Each contributor's own answer, handed back under the key it arrived on.
  # `modules/lab/cluster/` lowers this into the cluster's `delivery` record and
  # used to read the export off the lab's link instead — which a seal around
  # the lab's units refuses, and which this is the replacement for. The fan-in
  # carries the cluster's name, so the collector can key by it.
  testItHandsEachClusterItsOwnAnswerBack = {
    expr = (cdOf kappLab).perCluster;
    expected.stub-delivery = {
      strategy = "kapp";
      waitTimeout = "5m";
    };
  };

  # Nothing took over, so `cata` does the applying and the bootstrap is the
  # server-side applier that reads `.wave-meta`. No git, no root Application,
  # and none of the four handover steps.
  testAKappLabHandsNothingOver = {
    expr = {
      inherit (cdOf kappLab) bootstrap git rootApplication;
      steps = lib.attrNames (stepsOf kappLab);
    };
    expected = {
      bootstrap = "kubectl-ssa";
      git = { };
      rootApplication = { };
      steps = [ ];
    };
  };

  # A lab with no applier at all still answers, because the field is what the
  # CLI parses and `policies.oneDelivery` is what refuses a cluster with none.
  # This floe is not the place that question is asked.
  testWithNoPolicyItStillAnswers = {
    expr = (cdOf (deliveryWith [ "delivery" ])).bootstrap;
    expected = "kubectl-ssa";
  };

  # And with a repository but nothing that applies through it, there is still
  # nothing to hand over: a git server is a workload like any other until
  # something says it is where the manifests go.
  testARepositoryAloneIsNotAHandover = {
    expr = (cdOf (deliveryWith [ "delivery" ])).rootApplication;
    expected = { };
  };

  # The handover, which this suite claimed in its header and never ran: one
  # cluster says it runs Argo, a repository says where the tree goes, and four
  # steps appear naming that cluster — legally, because the name is the
  # collection's key rather than one the floe went looking for.
  testAGitopsLabHandsOverToTheClusterThatSaidSo =
    let
      gitops = gitopsWith { };
    in
    {
      expr = {
        steps = lib.attrNames (stepsOf gitops);
        target = (stepsOf gitops).apply-root-application.params.target;
        path = (cdOf gitops).rootApplication.spec.source.path;
      };
      expected = {
        steps = [
          "apply-root-application"
          "bootstrap-argocd"
          "bootstrap-repos"
          "publish-manifests"
        ];
        target = "stub-delivery";
        path = "manifests/stub-delivery";
      };
    };

  # The push runs from the *host* and goes through the routed name, so the
  # clone URL is the external one. Only Argo's `repoURL` is rewritten to the
  # internal address, because the thing reading that one is inside the cluster.
  testOnlyArgoReadsTheInternalAddress = {
    expr = {
      push = (cdOf (gitopsWith { })).git.repo;
      argo = (cdOf (gitopsWith { })).rootApplication.spec.source.repoURL;
    };
    expected = {
      push = "https://git.stub.test/stub-admin/lab.git";
      argo = "http://forgejo-http.forgejo.svc.cluster.local:3000/stub-admin/lab.git";
    };
  };
}
