# A frame: what every floe of a kind has, whatever else its author declares.
#
# Two kinds of floe in this distribution carry one. A cluster has namespaces,
# so it has the two controls over all of them and the policies about a
# cluster's units. A lab has an allocation and a set of units, so it has the
# nine inputs every lab has and the policies whose subject is a cluster.
#
# A transformation on `mkFloe`'s arguments rather than a constructor, because
# that is all the two have in common: `mkClusterFloe` is `mkFloe` over framed
# arguments and nothing else, and `mkLabFloe` is that plus a body of its own.
# A constructor covering both would need a hook for the difference, which is
# more machinery than the five lines it would save.
{
  lib,
  floe,
}:

let
  # refineInputs :: base -> own -> inputs
  #
  #   refineInputs labInputs { zone.default = "minimal.test"; }
  #
  # A floe may *refine* one of its frame's inputs rather than redeclare it.
  # Every lab has a `zone` and the type and the description of it belong to the
  # frame; which one is this lab's own fact, so what the author writes is the
  # default alone. Redeclaring would mean copying the paragraph that explains
  # what a zone is into six labs, where six copies could disagree.
  #
  # A name the frame does not declare is a new input, which is the ordinary
  # case: `inputs.tls = lib.mkOption { … }`.
  refineInputs =
    base: own:
    lib.mapAttrs (name: decl: decl // (own.${name} or { })) base
    // removeAttrs own (lib.attrNames base);

  # framedArgs :: frame -> mkFloe-args -> mkFloe-args
  #
  # The frame applied: its inputs refined by the author's, and its policies
  # unless the author named their own list.
  framedArgs =
    { baseInputs, policies }:
    args:
    args
    // {
      inputs = refineInputs baseInputs (args.inputs or { });
      policies = args.policies or policies;
    };

  # mkFramedFloe :: frame -> mkFloe-args -> callable floe definition
  #
  # For a kind whose frame is the whole of what it adds. Callable, so
  # `clusters.app { }` instantiates it the way `floes.podinfo { }` does;
  # `lib/lab.nix` does the same to the catalogue, and a lab's own floes should
  # not behave differently.
  mkFramedFloe =
    frame: args:
    let
      def = floe.mkFloe (framedArgs frame args);
    in
    def // { __functor = _: def.instantiate; };
in
{
  inherit framedArgs mkFramedFloe;
}
