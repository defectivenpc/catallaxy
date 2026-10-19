{
  lib,
  catallaxy,
}:

{
  linkLab =
    {
      labName,
      instance,
      catalogue,
    }:
    let
      prefix = lib.throwIf (lib.hasInfix "/" labName) (
        "lab '${labName}': the name holds a '/', which is how the linker qualifies "
        + "a unit inside an inclusion. A lab is one unit of one link and everything it holds "
        + "is named `<lab>/<unit>`, so the name has to be free of it."
      ) "${labName}/";

      strip = lib.mapAttrs' (n: v: lib.nameValuePair (lib.removePrefix prefix n) v);

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

      outer = catallaxy.floe.link {
        units.${labName} = instance;
        inherit catalogue;
      };

      link = outer // {
        out = lib.mapAttrs (_kind: strip) outer.out;
        floeNames = strip outer.floeNames;

        wiring = {
          one = strip (lib.mapAttrs (_: lib.mapAttrs (_: provider)) outer.wiring.one);
          optional = strip (lib.mapAttrs (_: lib.mapAttrs (_: provider)) outer.wiring.optional);
          all = strip (lib.mapAttrs (_: lib.mapAttrs (_: map provider)) outer.wiring.all);
        };
      };

      fold = kind: lib.foldl' lib.mergeAttrs { } (lib.attrValues (link.out.${kind} or { }));

      labSecrets = fold "catallaxy.labSecrets";

      unitsRunning = floeName: lib.attrNames (lib.filterAttrs (_: name: name == floeName) link.floeNames);
    in
    {
      inherit link;

      cdArrangement = catallaxy.cdArrangementOf link;

      hasIngress = unitsRunning "lab-proxy" != [ ];

      mirrors = unitsRunning "lab-registry";

      services = fold "catallaxy.labServices";

      steps = fold "catallaxy.labSteps";

      secrets = {
        stores = fold "catallaxy.labStores";
        managed = labSecrets;

        hostProjections = lib.concatLists (
          lib.mapAttrsToList (
            secretName: sec:
            lib.mapAttrsToList (key: hostPath: {
              inherit secretName key hostPath;
              inherit (sec) store kind;
            }) sec.hostPaths
          ) labSecrets
        );
      };
    };
}
