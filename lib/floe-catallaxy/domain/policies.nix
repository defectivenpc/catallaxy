{ lib, sigs }:

let
  clustersIn = result: result.out."catallaxy.cluster" or { };
  componentsIn = result: result.out."catallaxy.component" or { };
in
{
  providersVerifyWhatTheyPromise =
    result:
    let
      components = componentsIn result;

      obligated = lib.filterAttrs (_: sig: (sig.behaviour or [ ]) != [ ]) sigs;

      missingFor =
        sigName: sig:
        lib.concatMap (
          p:
          let
            c = components.${p.instName} or { };

            declared = lib.unique (
              lib.attrNames (c.verify or { })
              ++ lib.concatMap (b: lib.attrNames (b.verify or { })) (lib.attrValues (c.bundles or { }))
            );
            missing = lib.subtractLists declared sig.behaviour;
          in
          lib.optional (components ? ${p.instName} && missing != [ ]) (
            "'${p.instName}' provides '${sigName}' (as ${p.provideName}) and declares no "
            + "${lib.concatMapStringsSep " or " (c: "`verify.${c}`") missing}. "
            + "Shape is checked at link; this is the part of the promise shape cannot "
            + "express, so a provider of '${sigName}' owes a runtime check that it holds."
          )
        ) (result.providersOf sigName);
    in
    lib.concatLists (lib.mapAttrsToList missingFor obligated);

  oneDelivery =
    result:
    let
      providers = result.providersOf "DELIVERY_POLICY";
      named = lib.concatMapStringsSep ", " (p: "'${p.instName}'") providers;
    in
    if providers == [ ] then
      [
        (
          "no unit says how this cluster's content reaches it. Add a delivery floe: "
          + "`floes.kapp { }` for an apply `cata` performs, or a CD tool that takes it over."
        )
      ]
    else
      lib.optional (lib.length providers > 1) (
        "${toString (lib.length providers)} units provide DELIVERY_POLICY (${named}). "
        + "One cluster is applied one way, so one of them has to go."
      );

  promisedHostsAreRouted =
    result:
    let
      carried = lib.attrNames (
        lib.filterAttrs (
          unit: provs: provs != { } && ((componentsIn result).${unit} or { bundles = { }; }).bundles == { }
        ) result.provides
      );

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
          ) (removeAttrs result.provides carried)
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

  kanidmPrincipalsAreUnique =
    result:
    let
      principalKinds = [
        "KanidmOAuth2Client"
        "KanidmServiceAccount"
        "KanidmPersonAccount"
        "KanidmGroup"
      ];

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

  componentsTargetTheCluster =
    result:
    let
      clusters = lib.attrNames (clustersIn result);
      reaches =
        from: to: lib.any (e: e.from == from && e.to == to && e.kind == "eval") result.graph.edges;
      installs = lib.filterAttrs (_: c: c.bundles != { }) (componentsIn result);

      ancestors =
        unit:
        let
          parts = lib.splitString "/" unit;
        in
        map (n: lib.concatStringsSep "/" (lib.take n parts)) (lib.range 1 (lib.length parts));

      covered =
        unit: lib.any (u: lib.elem u clusters || lib.any (c: reaches u c) clusters) (ancestors unit);
    in
    lib.concatMap (
      unit:
      lib.optional (!(covered unit))
        "unit '${unit}' renders bundles but requires no cluster. Add `requires.cluster = sigs.KUBERNETES_CLUSTER`."
    ) (lib.attrNames installs);

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
