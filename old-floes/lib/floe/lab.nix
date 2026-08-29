# The lab extension: what a floe additionally is when it lives at lab scope.
#
# Small, and that is the finding. `modules/lab/lab-floe-options.nix` declares
# seven channels; six of them — `enable`, `version`, `infra.resources`, `ops`,
# `lint`, `verify` — are in the base, shared verbatim with the cluster scope.
# The seventh, `steps`, is shared by name but not by type: a lab step runs once
# for the lab and carries no `scope`, so each extension declares its own.
#
# What is genuinely lab-only is `clusters`. Everything else a lab floe does it
# does by holding sub-floes (`floes.<name>` in the base) or by writing lab
# configuration directly.
{ modulesPath }:

{ lib, ... }:

let
  inherit (lib) mkOption types;

  inherit (import (modulesPath + "/lab/planner/types.nix") { inherit lib; }) declaredStepType;
in
{
  _class = "catallaxyFloe";

  options = {
    steps = mkOption {
      type = types.attrsOf declaredStepType;
      default = { };
      description = ''
        Plan steps this floe contributes, lifted into `lab.steps` under the
        key it was given here.

        Lab-scope throughout: a step here runs once for the lab, not once per
        cluster, which is why it has no `scope` field. A step that acts on one
        cluster belongs to a cluster floe — which, now that a floe can hold
        floes, means a sub-floe of this one.
      '';
    };

    clusters = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "app" ];
      description = ''
        Clusters this platform provisions.

        A cluster the lab declares and this list omits is left alone, which is
        how a lab runs two platforms side by side.
      '';
    };

    labConfig = mkOption {
      type = types.attrs;
      default = { };
      example = lib.literalExpression "{ dns.enable = true; proxy.enable = true; }";
      description = ''
        Lab configuration this floe contributes, merged into the lab's own
        `lab` option tree.

        `types.attrs` rather than a channel per setting, and the tradeoff is
        worth stating plainly: nothing is type-checked *here*. It is checked
        where it lands — `lab.dns.enable` is a declared option, so a typo or a
        wrong type fails at the fold with the lab's own error message, naming
        the real option path. The same bargain `ingress` makes on the cluster
        extension.

        The alternative — one typed channel per lab setting — was rejected as
        a second copy of the lab's option tree that would have to be kept in
        step with it by hand. A floe writing `lab.dns.enable` is not extending
        the interface, it is configuring the thing it is part of, and there is
        no version of that which the interface can usefully type.

        What a lab floe *does* own, and what is typed, is `exports`,
        `capabilities`, `clusters`, `steps`, `ops`, `lint`, `verify` and
        `infra.resources`.
      '';
    };
  };
}
