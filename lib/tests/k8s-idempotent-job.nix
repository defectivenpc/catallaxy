{ lib }:

let
  job = import ../kubernetes/idempotent-job.nix { inherit lib; };

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

  testTheSameDeclarationIsTheSameJob = {
    expr = (mk { }).name == (mk { }).name;
    expected = true;
  };

  testChangingWhatWasAskedForRunsItAgain = {
    expr = (mk { }).name == (mk { contentInputs.kv = "other"; }).name;
    expected = false;
  };

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

  testBehaviourVersionForcesARerun = {
    expr = (mk { }).name == (mk { behaviourVersion = 2; }).name;
    expected = false;
  };

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

  testTheSelectorPinsThisGenerationOnly = {
    expr = lib.hasInfix "catallaxy.io/idempotent-job-hash=" (mk { }).selector;
    expected = true;
  };

  testTheOwnerConfigMapRecordsTheGeneration = {
    expr = lib.attrNames (mk { }).resources."openbao-init-runs".data;
    expected = [ (mk { }).hash ];
  };

  testItRetries = {
    expr = (mk { }).resources.${(mk { }).name}.spec.backoffLimit > 1;
    expected = true;
  };
}
