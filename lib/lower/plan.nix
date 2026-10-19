{
  lib,
  catallaxy,
}:

let
  t = import ../plan-tokens.nix { inherit lib; };
  inherit (import ../eval/anchors.nix { }) needs wants;
  planGraph = import ../eval/plan-graph.nix { inherit lib; };
  infraLib = import ../render/infra.nix { inherit lib; };
  kindTable = import ./plan-kinds { inherit lib; };

  variantOf = c: lib.head (lib.attrNames c.spec.provisioning.config);
in
{
  frameworkSteps =
    {
      clusters,
      services,
      link,
    }:
    let
      clusterNames = lib.attrNames clusters;

      hasServices = services != { };

      onDockerNetwork = name: !(clusters.${name}.spec.provisioning.config ? external);

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
        lib.optionalAttrs hasServices {
          setup-services = {
            kind = "setup-services";
            description = "Start lab infrastructure services";
            provides = [ t.lab.services ];
            after = [ (needs t.lab.network) ];
          };

          remove-services = {
            kind = "remove-services";
            description = "Remove lab infrastructure services";
            provides = [ t.lab.servicesRemoved ];

            after = map (n: wants (t.cluster n).destroyed) clusterNames;
            before = [ (wants t.lab.networkRemoved) ];
          };
        }

        // infraSteps

        // provisions.steps

        // lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (name: c: {
            "create-cluster-${name}" = {
              kind = "create-cluster";
              description = "Create ${variantOf c} cluster '${name}'";
              cluster = name;
              provides = [ (t.cluster name).created ];

              after = lib.optional (onDockerNetwork name) (needs t.lab.network) ++ provisions.extraAfterFor name;
              params = {
                inherit name;
                provisioner = variantOf c;
              };
            };

            "deploy-manifests-${name}" = {
              kind = "deploy-manifests";
              description = "Deploy manifests to '${name}'";
              cluster = name;
              provides = [ (t.cluster name).deployed ];
              after = [ (needs (t.cluster name).created) ];
              params = {
                target = name;
                bootstrap = false;
                kubeContext = c.spec.clusterHandle.context;
              };
            };

            "destroy-cluster-${name}" = {
              kind = "destroy-cluster";
              direction = "teardown";
              description = "Destroy ${variantOf c} cluster '${name}'";
              cluster = name;
              provides = [ (t.cluster name).destroyed ];

              after = provisions.teardownAfterFor name;
              params = {
                inherit name;
                provisioner = variantOf c;
                skipIfMissing = true;
              };
            };
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
                    (builtins.removeAttrs step [ "teardown" ])
                    // {
                      cluster = clusterName;
                      inherit origin;
                    }
                    // lib.optionalAttrs (step.teardown or null == "before-cluster-destroy") {
                      before = (step.before or [ ]) ++ [ (wants (t.cluster clusterName).destroyed) ];
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

        else if !(kindTable ? ${step.kind}) then
          throw ''
            step '${name}' (${step.origin}) has kind '${step.kind}', which is not
            one of the ${toString (lib.length (lib.attrNames kindTable))} the CLI implements.
          ''
        else if lib.length kindTable.${step.kind}.directions == 1 then
          lib.head kindTable.${step.kind}.directions
        else
          throw ''
            step '${name}' (${step.origin}) has kind '${step.kind}', which runs in
            ${lib.concatStringsSep " and " kindTable.${step.kind}.directions}, and does not say which
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
          kind = kindTable.${step.kind} or null;
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

      unknownKinds = lib.mapAttrsToList (
        name: step:
        "step '${name}' (${step.origin}) has kind '${step.kind}', which is not one of the ${toString (lib.length (lib.attrNames kindTable))} the CLI implements"
      ) (lib.filterAttrs (_: step: !(kindTable ? ${step.kind})) allSteps);

      wrongDirection = lib.concatLists (
        lib.mapAttrsToList (
          name: step:
          let
            kind = kindTable.${step.kind} or null;
            want = if step.direction == null then null else step.direction;
          in
          lib.optional (kind != null && want != null && !(lib.elem want kind.directions))
            "step '${name}' (${step.origin}) is declared in the ${want} plan, and kind '${step.kind}' only runs in ${lib.concatStringsSep " or " kind.directions}"
        ) allSteps
      );
    in
    {
      assertions = map (message: {
        assertion = false;
        inherit message;
      }) (unknownKinds ++ wrongDirection);

      warnings =
        planGraph.floatingSteps { steps = toGraph (inDirection "deploy"); }
        ++ planGraph.floatingSteps { steps = toGraph (inDirection "teardown"); };

      deploymentPlan = map (s: lower s.name) (ordered "deploy");
      teardownPlan = map (s: lower s.name) (ordered "teardown");
    };
}
