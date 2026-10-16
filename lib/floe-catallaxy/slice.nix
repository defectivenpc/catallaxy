# One cluster's view of the lab's link.
#
# A lab links its clusters as units, so there is one link and one set of
# flattened views over it: output keyed `<cluster>/<unit>`, wiring keyed the
# same way, each provider's `instName` qualified to match. Elaboration is
# per cluster, because a cluster is what applies — so it is handed the lab's
# link narrowed to one cluster and shortened back to the names that cluster
# knows its own units by.
#
# It is a view and not a second link. Nothing here re-resolves anything: the
# resolution happened once, at the lab, and this reads it. That is the whole
# reason the inner wiring had to surface at the parent (the floe interface's
# ADR 0010) — without it a component inside a cluster had no resolution to
# read, and every bundle-to-bundle edge the elaborator derives would have
# vanished.
{ lib }:

let
  # `<cluster>/<unit>` -> `<unit>`, for the keys and for the provider names
  # inside the entries. Only what belongs to this cluster: a lab's own floes
  # sit beside the clusters and are nobody's units.
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
  # sliceFor :: { clusterName; provisionerFrom; } -> LinkResult -> LinkResult-shaped view
  #
  # Only the fields elaboration reads, deliberately: a view that answered
  # every question a link does would be a second link, and a reader could
  # not tell which one it had.
  #
  # `provisionerFrom` is the lab unit that answered this cluster's hole. The
  # provisioner sits beside the cluster rather than inside it — that is what
  # lets one cluster floe be k3d here and Talos elsewhere — so its descriptor
  # is keyed by its own name and the narrowing above would drop it, leaving
  # elaboration a cluster with no cluster in it. The descriptor cannot travel
  # through `KUBERNETES_CLUSTER` instead: that carries the handle, and this
  # also carries the provisioning, which ADR 0001 is the reason to keep apart.
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
