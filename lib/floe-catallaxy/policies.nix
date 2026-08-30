# Link-time policies: functions over the link result returning violations.
# Core owns coherence — exactly one provider, sealed provides. A policy owns
# domain legality, which core has no vocabulary for.
#
# Checks that need the *joined* cluster rather than the collection live in
# ./elaborate.nix instead: a namespace with no creator cannot be answered by
# any one floe, so it is not a policy over the link result.
{ lib }:

let
  clustersIn = result: result.out."catallaxy.cluster" or { };
  componentsIn = result: result.out."catallaxy.component" or { };
in
{
  # This link is cluster-scope, not lab-scope. A second cluster would mean the
  # components below have two candidate targets and nothing says which, so it
  # is refused here rather than resolved by guesswork.
  oneCluster =
    result:
    let
      names = lib.attrNames (clustersIn result);
    in
    if names == [ ] then
      [ "no unit provides a cluster: nothing here has anywhere to install to" ]
    else
      lib.optional (lib.length names > 1) (
        "this link is cluster-scope but ${toString (lib.length names)} units "
        + "provide a cluster: ${lib.concatStringsSep ", " names}. "
        + "Assembling several is a lab, which is not built yet."
      );

  # A unit that *installs* into the cluster has to have said so. The eval edge
  # exists because it resolved KUBERNETES_CLUSTER; a unit rendering bundles
  # with no such edge is reading cluster facts from somewhere it should not,
  # or is about to render something that lands wherever kubectl points.
  #
  # Bundles, not components: a floe can emit a component and install nothing —
  # `delivery` carries a policy value and no manifests — and requiring it to
  # name a cluster it never touches would be asking for a dependency to
  # satisfy a check rather than because it is true.
  componentsTargetTheCluster =
    result:
    let
      clusters = lib.attrNames (clustersIn result);
      reaches =
        from: to: lib.any (e: e.from == from && e.to == to && e.kind == "eval") result.graph.edges;
      installs = lib.filterAttrs (_: c: c.bundles != { }) (componentsIn result);
    in
    lib.concatMap (
      unit:
      lib.optional (!(lib.elem unit clusters) && !(lib.any (c: reaches unit c) clusters))
        "unit '${unit}' renders bundles but requires no cluster. Add `requires.cluster = sigs.KUBERNETES_CLUSTER`."
    ) (lib.attrNames installs);

  # `needs` names a sibling in the floe's own bundle namespace. Naming
  # something that is not there is caught here rather than at the graph, where
  # the message would be about an unresolvable anchor on a qualified key the
  # author never wrote.
  needsNameSiblings =
    result:
    lib.concatLists (
      lib.mapAttrsToList (
        unit: component:
        let
          siblings = lib.attrNames component.bundles;
        in
        lib.concatLists (
          lib.mapAttrsToList (
            bundleName: bundle:
            map (
              n:
              "bundle '${unit}.${bundleName}' needs '${n}', which is not a bundle of '${unit}'. "
              + "`needs` is intra-floe; it has: ${lib.concatStringsSep ", " siblings}."
            ) (lib.filter (n: !(lib.elem n siblings)) bundle.needs)
          ) component.bundles
        )
      ) (componentsIn result)
    );

  # `backs` says which of a floe's own bundles stand behind a provide, so it
  # can only name its own.
  backsNameOwnBundles =
    result:
    lib.concatLists (
      lib.mapAttrsToList (
        unit: component:
        let
          siblings = lib.attrNames component.bundles;
        in
        lib.concatLists (
          lib.mapAttrsToList (
            instance: named:
            map (n: "'${unit}' backs provide '${instance}' with '${n}', which is not one of its bundles.") (
              lib.filter (n: !(lib.elem n siblings)) named
            )
          ) component.backs
        )
      ) (componentsIn result)
    );
}
