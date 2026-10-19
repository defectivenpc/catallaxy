{
  lib,
  floe,
}:

let
  refineInputs =
    base: own:
    lib.mapAttrs (name: decl: decl // (own.${name} or { })) base
    // removeAttrs own (lib.attrNames base);

  framedArgs =
    { baseInputs, policies }:
    args:
    args
    // {
      inputs = refineInputs baseInputs (args.inputs or { });
      policies = args.policies or policies;
    };

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
