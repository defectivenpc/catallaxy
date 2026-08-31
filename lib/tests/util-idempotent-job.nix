# The idempotent Job.
#
# Kubernetes has no "run once, unless what it does has changed" primitive, and
# a Job is immutable — so a re-render either collides with the existing one or
# needs a new name. Naming it after a hash of the *declaration* is what makes
# the name change exactly when the intent does.
{ lib }:

let
  job = import ../util/idempotent-job.nix { inherit lib; };

  base = {
    name = "openbao-init";
    namespace = "openbao";
    contentInputs.kv = "secret";
    podSpec.containers = [
      {
        name = "init";
        image = "a:1";
      }
    ];
  };

  mk = attrs: job.mkIdempotentJob (lib.recursiveUpdate base attrs);
in
lib.runTests {

  # The whole point. Re-rendering the same declaration must produce the same
  # Job name, or every `lab up` runs the payload again — against a live API,
  # which for an init Job means re-provisioning something already provisioned.
  testTheSameDeclarationIsTheSameJob = {
    expr = (mk { }).name == (mk { }).name;
    expected = true;
  };

  testChangingWhatWasAskedForRunsItAgain = {
    expr = (mk { }).name == (mk { contentInputs.kv = "other"; }).name;
    expected = false;
  };

  # The hash covers what you declared, not how you implemented it.
  # Reformatting the payload's script or bumping its base image is not a
  # change of desired state and must not re-run a Job against a live API.
  testChangingTheImplementationDoesNot = {
    expr =
      (mk { }).name == (mk {
        podSpec.containers = [
          {
            name = "init";
            image = "a:2";
          }
        ];
      }).name;
    expected = true;
  };

  # The escape hatch for what a declaration cannot express: the payload does
  # something different while everything it was given is the same.
  testBehaviourVersionForcesARerun = {
    expr = (mk { }).name == (mk { behaviourVersion = 2; }).name;
    expected = false;
  };

  # Recorded but not acted on, so a reader — or a check — can see that a
  # payload changed while its declared inputs did not. That is either a
  # cosmetic edit or a forgotten `behaviourVersion` bump, and the difference
  # matters enough to be visible.
  testTheImplementationHashIsRecordedSeparately =
    let
      a = mk { };
      b = mk {
        podSpec.containers = [
          {
            name = "init";
            image = "a:2";
          }
        ];
      };
      annotationOf = r: r.resources.${r.name}.metadata.annotations."catallaxy.io/implementation-hash";
    in
    {
      expr = annotationOf a == annotationOf b;
      expected = false;
    };

  # Waiting on `component=<name>` alone also selects every earlier hash, and
  # on the server-side-apply path nothing prunes them — so one failed Job from
  # a previous render makes the wait fail forever.
  testTheSelectorPinsThisGenerationOnly = {
    expr = lib.hasInfix "catallaxy.io/idempotent-job-hash=" (mk { }).selector;
    expected = true;
  };

  # One key per generation that has been applied, so what ever ran is readable
  # from the cluster rather than inferred from Job names something may have
  # pruned.
  testTheOwnerConfigMapRecordsTheGeneration = {
    expr = lib.attrNames (mk { }).resources."openbao-init-runs".data;
    expected = [ (mk { }).hash ];
  };

  # A Job that fails is retried, because the thing it talks to may simply not
  # be up yet — an init Job races the server it initialises.
  testItRetries = {
    expr = (mk { }).resources.${(mk { }).name}.spec.backoffLimit > 1;
    expected = true;
  };
}
