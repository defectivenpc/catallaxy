# What a step is, before and after the sort.
#
# In `lib/` rather than beside the planner because both sides of the contract
# read it: `modules/lab/planner` types the lab's own `lab.steps`, and
# `lib/floe-catallaxy/component.nix` types the `steps` a floe contributes, via
# `T.moduleType`. One spelling, so the two cannot disagree about what a step
# is.
#
# A step declares what it needs rather than where it goes. `after`/`before`
# name anchors — a token something publishes, a kind, or `optional:` either —
# and the planner resolves them into an order. That indirection is the whole
# point: a floe contributing a step cannot know what else is in the lab, so it
# cannot name a position, only a condition.
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

        Two consequences. It makes the lab ineligible for the e2e runner, via
        `lab.out.selfContained`. And it suppresses the retry its kind's
        idempotency class would otherwise get: re-running a step that opens a
        browser issues a fresh prompt while the first is still waiting, so the
        retry defeats the step it is retrying.
      '';
    };
  };
in
{
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

  inherit policyOptions;
}
