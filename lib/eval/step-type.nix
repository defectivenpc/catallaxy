# What a step is, before and after the sort.
{ lib }:

let
  inherit (lib) mkOption types;

  anchorType = types.str;

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
  # What a floe or a lab writes.
  declaredStepType = types.submodule (
    { name, ... }:
    {
      options = {
        kind = mkOption {
          type = types.str;
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

        policy = policyOptions;
      };
    }
  );
  # The one option `declaredStepType` is reached through, as a module.
  #
  # Two readers, and that it is one module is what keeps them honest: the merge
  # below, and `nix/option-docs.nix`, which runs `nixosOptionsDoc` over exactly
  # this to generate the step schema page. A schema page generated from
  # anything else could describe a field the merge does not accept.
  #
  # `_file` so the page can say where each field is declared. `internal`
  # because `steps` itself is not an authoring surface — it is the merge point
  # for the three producers — while the fields under it are what a floe writes.
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
  inherit declaredStepType stepsModule;

  # mergeSteps :: [{ StepName -> declaredStep }] -> { StepName -> step }
  #
  #   mergeSteps [ floeSteps frameworkSteps ]
  #
  # Every step a lab holds, from each of the three producers that contribute
  # one: the floes' through `lab-steps`, the framework's lifecycle steps, and
  # one set per provisioning edge.
  #
  # The merge is `evalModules` and not `//` for two reasons, and both are
  # load-bearing. A `//` would silently resolve two producers claiming one step
  # name, which is a step that vanishes rather than an error. And the type is
  # where every field a step does not state gets its default — `direction`
  # from the kind, `description` from the attribute name — so a set that has
  # not been through it is a different set.
  mergeSteps =
    producers:
    (lib.evalModules {
      modules = [ stepsModule ] ++ map (steps: { inherit steps; }) producers;
    }).config.steps;

  inherit policyOptions;
}
