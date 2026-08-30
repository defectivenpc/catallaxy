# The plan, derived rather than written out.
#
# `modules/lab/plan.nix` was a hand-written list, and said where this would go
# when a floe needed to contribute a step. Four do: external-dns has a
# teardown step, cilium's CNI has to land before the cluster is Ready, argocd
# hands the cluster over, and netbird's mesh join needs a human.
#
# A contributed step cannot know what else is in the lab, so it cannot name a
# position — only a condition. `after`/`before` name anchors, the kinds table
# says which direction a step may run in and how it retries, and the order is
# what falls out.
{
  config,
  lib,
  ...
}:

let
  inherit (lib) mkOption types;

  stepTypes = import ./types.nix { inherit lib; };
  planGraph = import ../../../lib/eval/plan-graph.nix { inherit lib; };
  kindTable = import ./kinds { inherit lib; };

  clusters = config.lab.clusters;

  # A floe's steps, stamped with the floe that declared them and the cluster
  # they act on. A lab names units, so the *unit* is what an error should
  # name — that is what the deployer can find.
  floeSteps = lib.concatLists (
    lib.mapAttrsToList (
      clusterName: cluster:
      lib.concatLists (
        lib.mapAttrsToList (
          unit: steps:
          lib.mapAttrsToList (stepName: step: {
            name = "${clusterName}-${stepName}";
            value = step // {
              cluster = clusterName;
              origin = "floe '${unit}' on cluster '${clusterName}'";
            };
          }) steps
        ) (cluster.out.steps or { })
      )
    ) clusters
  );

  labSteps = lib.mapAttrsToList (name: step: {
    inherit name;
    value = step // {
      origin = "lab.steps.${name}";
    };
  }) config.lab.steps;

  allSteps = lib.listToAttrs (labSteps ++ floeSteps);

  # A kind that runs in exactly one direction says so, and a step that repeats
  # it is a second place for the two to disagree.
  directionOf =
    name: step:
    if step.direction != null then
      step.direction

    # An unknown kind lands here too, and the "more than one direction"
    # message would be a lie about a kind that does not exist. `unknownKinds`
    # below says the true thing, but it is an assertion and this is a throw,
    # so this one wins the race and has to be right on its own.
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

  # `plan-graph` wants the anchor vocabulary and nothing else, so each step is
  # lowered to it and the result is read back through `allSteps`.
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
      steps = toGraph (inDirection want);
    in
    planGraph.topoSort { inherit steps; };

  # What the CLI parses. `policy.retry` is the kind's idempotency class, not
  # the author's: running `create-cluster` twice is not the same as running it
  # once, and that is a property of the kind.
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
      # `interactive` goes out as itself rather than being folded into
      # `retry`. `PlannedStep::attempts` (cli/src/domain/plan.rs:145) already
      # returns 1 for an interactive step, so folding would say the same thing
      # twice — and it would erase the flag, which `lab plan --stable` prints
      # and a reader needs to see to know why the step will not be retried.
      policy = {
        inherit retry;
        inherit (step.policy) onFailure interactive;
      };
    };

  # ---- what the sort cannot catch ---------------------------------------

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

  options.lab.out.deploymentPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab up` executes.";
  };

  options.lab.out.teardownPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab destroy` executes.";
  };

  options.lab.steps = mkOption {
    type = types.attrsOf stepTypes.declaredStepType;
    default = { };
    description = ''
      Steps the lab itself contributes, beside the ones the framework emits
      and the ones its floes declare.

      For work that is neither applying a manifest nor provisioning: checking
      a precondition, running a script, waiting on something outside the
      cluster.
    '';
  };

  config.lab.assertions = map (message: {
    assertion = false;
    inherit message;
  }) (unknownKinds ++ wrongDirection);

  # `topoSort` hands back the graph records with their names; the payload the
  # CLI reads comes from the declaration, not from the lowering the sort saw.
  config.lab.out.deploymentPlan = map (s: lower s.name) (ordered "deploy");
  config.lab.out.teardownPlan = map (s: lower s.name) (ordered "teardown");
}
