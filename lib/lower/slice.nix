{ lib }:

let
  narrow =
    clusterName:
    let
      prefix = "${clusterName}/";
      mine = lib.filterAttrs (k: _: lib.hasPrefix prefix k);
      shorten = lib.mapAttrs' (k: v: lib.nameValuePair (lib.removePrefix prefix k) v);
    in
    {
      inherit prefix;
      keys = byUnit: shorten (mine byUnit);

      provider =
        p:
        if p == null then
          null
        else
          p
          // {
            instName = lib.removePrefix prefix p.instName;
          }
          // lib.optionalAttrs (p ? backedBy) { backedBy = lib.removePrefix prefix p.backedBy; };
    };
in
{
  sliceFor =
    { clusterName, provisionerFrom }:
    labLink:
    let
      at = narrow clusterName;

      claimed =
        kind:
        lib.optionalAttrs (labLink.out.${kind} or { } ? ${provisionerFrom}) {
          ${provisionerFrom} = labLink.out.${kind}.${provisionerFrom};
        };
    in
    {
      out = lib.mapAttrs (kind: byUnit: at.keys byUnit // claimed kind) labLink.out;

      floeNames = at.keys labLink.floeNames // {
        ${provisionerFrom} = labLink.floeNames.${provisionerFrom};
      };

      wiring = {
        one = at.keys (lib.mapAttrs (_: lib.mapAttrs (_: at.provider)) labLink.wiring.one);
        optional = at.keys (lib.mapAttrs (_: lib.mapAttrs (_: at.provider)) labLink.wiring.optional);
        all = at.keys (lib.mapAttrs (_: lib.mapAttrs (_: map at.provider)) labLink.wiring.all);
      };
    };
}
