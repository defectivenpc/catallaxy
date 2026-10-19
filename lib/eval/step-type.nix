{
  lib,
  planTokens,
  stepKinds,
}:

let
  inherit (lib) mkOption types;

  anchorType = types.str;

  clusterStates = lib.attrNames (planTokens.cluster "any");
  labPhases = lib.attrNames planTokens.lab;

  condition =
    scope: states:
    mkOption {
      type = types.nullOr (types.enum states);
      default = null;
      description = ''
        When this step runs relative to ${scope}, as a condition rather than an
        anchor: the floe has no name for a cluster it is not in, and no business
        spelling a token.

        Expanded into one anchor per ${scope} by `lab-steps`, which is the only
        unit that knows the names. Tolerant on each — a lab with no ${scope}
        matching leaves the step unordered rather than refused.
      '';
    };

  conditionOptions = {
    beforeClusters = condition "every cluster" clusterStates;
    afterClusters = condition "every cluster" clusterStates;

    beforeLab = condition "the lab phase" labPhases;
    afterLab = condition "the lab phase" labPhases;
  };

  policyOptions = {
    onFailure = mkOption {
      type = types.enum [
        "fatal"
        "continue"
      ];
      default = "fatal";
      description = ''
        Whether the run stops here.

        `continue` is for teardown, where a step that cannot finish must not
        strand the ones after it — a cluster that is already gone should not
        prevent removing the network it was on.
      '';
    };

    interactive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        The step cannot finish without a human.

        It suppresses the retry its kind's idempotency class would otherwise
        get: re-running a step that opens a browser issues a fresh prompt
        while the first is still waiting, so the retry defeats the step it is
        retrying.
      '';
    };
  };
  declaredOptions = name: {
    kind = mkOption {
      type = types.enum (lib.attrNames stepKinds);
      description = ''
        Which of the 34 step kinds this is. The kind decides what params
        are legal, whether the step may run in a given direction, and the
        retry class the executor applies.
      '';
    };

    direction = mkOption {
      type = types.nullOr (
        types.enum [
          "deploy"
          "teardown"
        ]
      );
      default = null;
      description = ''
        Which plan it belongs to. Null takes the kind's, when the kind
        runs in exactly one — most do, and saying it twice is a way for
        the two to disagree.
      '';
    };

    after = mkOption {
      type = types.listOf anchorType;
      default = [ ];
      description = ''
        Anchors this step follows. `provides:<token>` waits on whatever
        publishes it, `kind:<kind>` on every step of that kind, and
        `optional:` either tolerates matching nothing.

        `optional:` is not a weaker edge — it is the difference between
        "after the DNS server, if this lab runs one" and "this lab must
        run a DNS server".
      '';
    };

    before = mkOption {
      type = types.listOf anchorType;
      default = [ ];
      description = ''
        Anchors this step precedes. Inverted into `after` edges on the
        other side, so a step can insert itself ahead of something that
        has never heard of it.
      '';
    };

    provides = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Tokens that are true once this step has run.";
    };

    teardown = mkOption {
      type = types.nullOr (types.enum [ "before-cluster-destroy" ]);
      default = null;
      description = ''
        A moment in the teardown, for a step a floe contributes. The
        planner turns it into the anchor, because it knows which cluster
        the floe is on and the floe does not — that is the whole point.
        A floe naming a plan token would be depending on lab internals
        the signatures exist to keep it away from.
      '';
    };

    params = mkOption {
      type = types.attrs;
      default = { };
      description = "Payload for the step kind, checked against its schema.";
    };

    description = mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalExpression "the attribute name";
      description = "One line, shown by `cata lab plan`.";
    };

    cluster = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Cluster this acts on, when it acts on one.";
    };

    origin = mkOption {
      type = types.str;
      default = "lab";
      description = ''
        Who declared it, for an error message to name.

        A floe's steps are stamped with the floe, because "step
        `mesh-join` names an anchor nothing provides" is not actionable
        without knowing which floe to open.
      '';
    };

    afterCluster = mkOption {
      type = types.nullOr (types.enum clusterStates);
      default = null;
      description = ''
        A state this step waits for *its own* cluster to reach.

        Distinct from `afterClusters`, which waits on every cluster: a unit of
        a cluster that needs its own kubeconfig on disk is saying something
        about one cluster, and naming the others would over-order the plan.
      '';
    };

    providesCluster = mkOption {
      type = types.nullOr (types.enum clusterStates);
      default = null;
      description = ''
        The state this step puts its cluster into, for a step a unit of a
        cluster contributes.

        The provide side of `beforeClusters`: a floe that creates a cluster
        says which state it reaches rather than spelling the token, because
        the name it would need is the lab's key for the cluster and the floe
        only has its own input. The planner knows both and expands it.
      '';
    };

    policy = policyOptions;
  };

  declaredStepType = types.submodule ({ name, ... }: { options = declaredOptions name; });

  authoredStepType = types.submodule (
    { name, ... }: { options = declaredOptions name // conditionOptions; }
  );

  stepsModule = {
    _file = toString ./step-type.nix;

    options.steps = mkOption {
      type = types.attrsOf declaredStepType;
      default = { };
      internal = true;
      description = "Every step a lab holds: its floes', the framework's, and provisioning's.";
    };
  };
in
{
  inherit declaredStepType authoredStepType stepsModule;

  mergeSteps =
    producers:
    (lib.evalModules {
      modules = [ stepsModule ] ++ map (steps: { inherit steps; }) producers;
    }).config.steps;
}
