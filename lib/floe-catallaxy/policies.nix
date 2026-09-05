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

  # A promise naming a hostname in the gateway's zone has to be served.
  #
  # kanidm promised `https://idm.<zone>` as its issuer and rendered no route
  # to it for the whole life of this tree. Every OIDC consumer — forgejo,
  # harbor, argocd, grafana, netbird — was configured against a name the lab
  # answered with a 503, and nothing caught it: `lab-routed-hosts-are-proxied`
  # checks the other direction, that a *route* has a backend, and an e2e that
  # never opens a browser never asks.
  #
  # So this is the missing half. A provide is a promise, and a promise
  # carrying an address inside the zone the gateway serves is a claim that
  # something routes it.
  #
  # Only hostnames in the zone: a signature may legitimately carry an address
  # somewhere else entirely — an upstream registry, a public issuer — and that
  # is not this cluster's to serve.
  promisedHostsAreRouted =
    result:
    let
      gateways = lib.filter (g: g != null) (
        lib.concatLists (
          lib.mapAttrsToList (
            _unit: provs: lib.mapAttrsToList (_n: v: if v ? baseDomain && v ? parentRef then v else null) provs
          ) result.provides
        )
      );
    in
    lib.optionals (gateways != [ ]) (
      let
        zone = (lib.head gateways).baseDomain;

        # Every `https://host...` and `http://host...` any unit promised.
        hostsIn =
          v:
          if builtins.isString v then
            let
              m = builtins.match "https?://([^/:]+).*" v;
            in
            lib.optional (m != null) (lib.head m)
          else if builtins.isAttrs v then
            lib.concatMap hostsIn (lib.attrValues v)
          else if builtins.isList v then
            lib.concatMap hostsIn v
          else
            [ ];

        promised = lib.concatLists (
          lib.mapAttrsToList (
            unit: provs:
            map (h: {
              inherit unit;
              host = h;
            }) (lib.concatMap hostsIn (lib.attrValues provs))
          ) result.provides
        );

        inZone = lib.filter (p: lib.hasSuffix ".${zone}" p.host) promised;

        routed = lib.concatLists (
          lib.mapAttrsToList (
            _unit: component:
            lib.concatLists (
              lib.mapAttrsToList (
                _b: bundle:
                lib.concatMap (r: lib.optionals ((r.kind or "") == "HTTPRoute") (r.spec.hostnames or [ ])) (
                  lib.attrValues bundle.resources
                )
                # Plus what an operator routes on the bundle's behalf, which
                # nothing in `resources` names.
                ++ bundle.routedHosts
              ) component.bundles
            )
          ) (componentsIn result)
        );
      in
      map (
        p:
        "unit '${p.unit}' promises '${p.host}', which is inside the gateway's zone "
        + "'${zone}', and nothing in this cluster routes it. Whatever reads that "
        + "promise reaches the lab's ingress and is answered 503 — by a component "
        + "that is running and healthy, which is why nothing reports it."
      ) (lib.filter (p: !(lib.elem p.host routed)) (lib.unique inZone))
    );

  # kanidm has one name namespace across every kind of principal.
  #
  # An OAuth2 client, a service account, a person and a group all become
  # entries with a `name` and an SPN, and two of them cannot share one. A
  # consumer cannot see this: it renders its own resource in its own namespace
  # and has no idea what another floe called its own.
  #
  # What it looks like when it happens is a 500 from kanidm and, in kaniop, a
  # `failed to create <name>` that repeats forever. The reason is only in
  # kanidm's log — `AttrUnique("duplicate value detected")` — and the resource
  # that lost is left with an empty status, so whatever was waiting on its
  # token waits for good. netbird hit exactly this: its client and its service
  # account were both called `netbird`.
  kanidmPrincipalsAreUnique =
    result:
    let
      principalKinds = [
        "KanidmOAuth2Client"
        "KanidmServiceAccount"
        "KanidmPersonAccount"
        "KanidmGroup"
      ];

      # The entry's name is `metadata.name` for every one of these kinds:
      # kaniop derives the principal from the resource's own name.
      claims = lib.concatLists (
        lib.mapAttrsToList (
          unit: component:
          lib.concatLists (
            lib.mapAttrsToList (
              bundleName: bundle:
              lib.concatMap (
                r:
                lib.optional (lib.elem (r.kind or "") principalKinds) {
                  inherit unit;
                  kind = r.kind;
                  name = r.metadata.name;
                }
              ) (lib.attrValues bundle.resources)
            ) component.bundles
          )
        ) (componentsIn result)
      );
    in
    lib.concatMap (
      name:
      let
        holders = lib.filter (c: c.name == name) claims;
      in
      lib.optional (lib.length holders > 1) (
        "kanidm principal '${name}' is claimed by "
        + lib.concatMapStringsSep " and " (h: "${h.unit}'s ${h.kind}") holders
        + ". kanidm has one name namespace across clients, service accounts, "
        + "people and groups; the second to reconcile gets a 500 and an empty "
        + "status, and whatever waits on it waits forever."
      )
    ) (lib.unique (map (c: c.name) claims));

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
