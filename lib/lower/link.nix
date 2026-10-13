# The lab's one link, and the folds every reader of it shares.
#
# One link whose units are the clusters, the claim that answers each, and the
# floes the lab holds itself — so a value reaching a cluster is the parent
# filling a hole that cluster declared, resolved by the same rule everything
# else is.
#
# What this replaces is three mechanisms in a row. `link`'s `scope` was a
# second resolution path consulted after local providers failed. Then crossing
# units: each cluster linked separately, and the lab injected a synthetic unit
# per value by reading every *other* cluster's link result — which terminated
# only because a cluster excluded its own contributions, and which meant two
# clusters could never fill each other's holes. The floe interface gained
# inclusion, so neither is needed: linking units yields a unit, and a cluster
# is one.
#
# The dependency runs one way, which is what makes it legal: authored floes ->
# this link -> each cluster's elaboration -> the lowering. The old shape had a
# cluster's link depending on its siblings' link results.
#
# The folds come back with it because every one of them is a read of this one
# value, and each used to be computed in whichever module wanted it — the host
# services in `modules/lab/host.nix`, the steps in `steps.nix`, the stores and
# the secrets in `secrets.nix`. Six answers to "what did the link say", in six
# places, over one link.
{
  lib,
  catallaxy,
}:

{
  # linkLab :: { labName; instance; catalogue; } -> folds
  #
  #   { link; cdArrangement; hasIngress; services; steps; secrets; }
  #
  # `instance` is the lab's own floe, instantiated: a pure inclusion whose
  # units are everything the lab holds. Nothing crosses out of a lab, so it
  # declares no inputs, no holes and no provides — and the point of it is the
  # other half of an inclusion. The units' `provides` are sealed, so no reader
  # of the link can see into them. Five readers used to, and every one of those
  # reads was legal — a parent reading a unit's declared export is the
  # interface working — but none was *declared*, and `or { }` on a read that
  # has stopped resolving defaults silently. ADR 0007.
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
