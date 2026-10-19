{
  lib,
  catallaxy,
}:

let
  t = import ../plan-tokens.nix { inherit lib; };
  inherit (import ../eval/anchors.nix { }) needs wants;
  planGraph = import ../eval/plan-graph.nix { inherit lib; };
  infraLib = import ../render/infra.nix { inherit lib; };
  inherit (catallaxy) stepKinds;

  variantOf = c: lib.head (lib.attrNames c.spec.provisioning.config);
in
{
  frameworkSteps =
    {
      clusters,
      link,
    }:
    let
      clusterNames = lib.attrNames clusters;

      stacks = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: c: c.stacks) clusters);

      phaseOfStack = name: (lib.head (lib.attrValues stacks.${name}.resources)).phase;

      stackDeps = name: infraLib.dependenciesOf stacks name;

      provisions = import ./plan-provisions.nix {
        inherit
          lib
          catallaxy
          t
          needs
          wants
          variantOf
          clusters
          link
          ;
        stackNames = lib.attrNames stacks;
      };

      infraSteps = lib.foldl' lib.mergeAttrs { } (
        lib.mapAttrsToList (
          stackName: _:
          let
            phase = phaseOfStack stackName;
            deps = stackDeps stackName;

            againstClusters =
              if phase == "before-clusters" then map (n: (t.cluster n).created) clusterNames else [ ];

            afterClusters = lib.optionals (phase == "after-clusters") (
              map (n: needs (t.cluster n).created) clusterNames
            );
          in
          {
            "infra-plan-${stackName}" = {
              kind = "infra-plan";
              description = "Plan stack '${stackName}'";

              provides = [ (t.stack stackName).planned ];
              after = map (d: needs (t.stack d).applied) deps ++ afterClusters;
              before = map (a: wants a) againstClusters;
              params.stack = stackName;
            };

            "infra-apply-${stackName}" = {
              kind = "infra-apply";
              description = "Apply stack '${stackName}'";
              provides = [ (t.stack stackName).applied ];
              after = [ (needs (t.stack stackName).planned) ];
              before = map (a: wants a) againstClusters;
              params.stack = stackName;
            };

            "infra-destroy-${stackName}" = {
              kind = "infra-destroy";
              description = "Destroy stack '${stackName}'";
              provides = [ (t.stack stackName).destroyed ];

              after =
                map (d: wants (t.stack d).destroyed) (
                  lib.filter (other: lib.elem stackName (stackDeps other)) (lib.attrNames stacks)
                )
                ++ map (n: wants (t.cluster n).destroyed) clusterNames;
              params.stack = stackName;
            };
          }
        ) stacks
      );
    in
    {
      assertions = provisions.assertions;

      steps =
        infraSteps

        // provisions.steps

        // lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (name: c: {

          }) clusters
        );
    };

  orderSteps =
    { clusters, steps }:
    let
      clusterSteps = lib.concatLists (
        lib.mapAttrsToList (
          clusterName: cluster:
          lib.concatLists (
            lib.mapAttrsToList (
              unit: unitSteps:
              lib.mapAttrsToList (
                stepName: step:
                let
                  origin = "floe '${unit}' on cluster '${clusterName}'";
                in
                {
                  name = "${clusterName}-${stepName}";
                  value =
                    (builtins.removeAttrs step [
                      "teardown"
                      "providesCluster"
                      "afterCluster"
                    ])
                    // {
                      cluster = clusterName;
                      inherit origin;
                    }
                    // lib.optionalAttrs (step.teardown or null == "before-cluster-destroy") {
                      before = (step.before or [ ]) ++ [ (wants (t.cluster clusterName).destroyed) ];
                    }
                    // lib.optionalAttrs (step.providesCluster != null) {
                      provides = step.provides ++ [ (t.cluster clusterName).${step.providesCluster} ];
                    }
                    // lib.optionalAttrs (step.afterCluster != null) {
                      after = step.after ++ [ (needs (t.cluster clusterName).${step.afterCluster}) ];
                    };
                }
              ) unitSteps
            ) (cluster.out.steps or { })
          )
        ) clusters
      );

      labSteps = lib.mapAttrsToList (name: step: {
        inherit name;
        value = step // {
          origin = "lab.steps.${name}";
        };
      }) steps;

      allSteps = lib.listToAttrs (labSteps ++ clusterSteps);

      directionOf =
        name: step:
        if step.direction != null then
          step.direction

        else if lib.length stepKinds.${step.kind}.directions == 1 then
          lib.head stepKinds.${step.kind}.directions
        else
          throw ''
            step '${name}' (${step.origin}) has kind '${step.kind}', which runs in
            ${lib.concatStringsSep " and " stepKinds.${step.kind}.directions}, and does not say which
            plan it belongs to. Set `direction`.
          '';

      inDirection = want: lib.filterAttrs (name: step: directionOf name step == want) allSteps;

      toGraph = lib.mapAttrs (
        _: step: {
          inherit (step) after before provides;
          requires = [ ];
          conflicts = [ ];
          inherit (step) kind origin;
        }
      );

      ordered =
        want:
        let
          inner = toGraph (inDirection want);
        in
        planGraph.topoSort { steps = inner; };

      lower =
        name:
        let
          step = allSteps.${name};
          kind = stepKinds.${step.kind} or null;
          retry = if kind == null then "idempotent" else kind.idempotency;
        in
        {
          inherit name;
          inherit (step)
            kind
            description
            params
            cluster
            origin
            ;
          policy = {
            inherit retry;
            inherit (step.policy) onFailure interactive;
          };
        };

      wrongDirection = lib.concatLists (
        lib.mapAttrsToList (
          name: step:
          let
            kind = stepKinds.${step.kind};
            want = step.direction;
          in
          lib.optional (want != null && !(lib.elem want kind.directions))
            "step '${name}' (${step.origin}) is declared in the ${want} plan, and kind '${step.kind}' only runs in ${lib.concatStringsSep " or " kind.directions}"
        ) allSteps
      );
    in
    {
      assertions = map (message: {
        assertion = false;
        inherit message;
      }) wrongDirection;

      warnings =
        planGraph.floatingSteps { steps = toGraph (inDirection "deploy"); }
        ++ planGraph.floatingSteps { steps = toGraph (inDirection "teardown"); };

      deploymentPlan = map (s: lower s.name) (ordered "deploy");
      teardownPlan = map (s: lower s.name) (ordered "teardown");
    };
}
