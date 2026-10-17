# Link-time policies: functions over the link result returning violations.
# Core owns coherence — exactly one provider, sealed provides. A policy owns
# domain legality, which core has no vocabulary for.
{ lib, sigs }:

let
  clustersIn = result: result.out."catallaxy.cluster" or { };
  componentsIn = result: result.out."catallaxy.component" or { };
in
{
  # A provider must verify what its signature promises.
  #
  # Compatibility settles a provider's *shape* — that `X509_ISSUANCE.issuerRef`
  # names an object, that `publicIssuer` is a bool. It cannot settle that the
  # issuer signs anything, and a ClusterIssuer that exists and never becomes
  # Ready leaves every Certificate pending while every check over rendered
  # output passes. That gap is NixOS RFC 0189's `behaviorTest`.
  #
  # The answer is not a new mechanism, which is the whole reason this is a
  # policy and not a library feature. Floes already declare runtime checks —
  # `verify.<name>` on a component, run by `cata lab verify` and by `cata-e2e`
  # against a real cluster. A signature names the checks any provider of it
  # owes, and this refuses a provider that declared none of them. The
  # obligation is inherited, which is the point: a second provider of
  # `API_GATEWAY` is told exactly which check it owes, and that is the
  # substitutability property the signature existed for.
  #
  # Two things it deliberately does not do. It does not judge the check —
  # "has one called `issuers-ready`" is weaker than "has a correct one", and
  # nothing static can close that. And it does not ask a unit that installs
  # nothing: a lab-scope floe, a provisioner, or a unit carrying a value in
  # from another cluster emits no component, so there is nothing of it running
  # to verify. Those are skipped rather than excused, because the absence of a
  # component is the honest signal and it needs no marking on the signature.
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

  # A cluster says how its content reaches it, exactly once.
  #
  # The other half of the pair: a cluster denotes a claim and its content,
  # and delivery is the function that
  # converges one onto the other, so a cluster with no answer has no way to be
  # applied and one with two has no way to choose. Absence used to mean kapp,
  # decided in `modules/lab/cd.nix` by finding no provider — so a lab that
  # meant to run Argo and forgot to add it was applied by hand, quietly, and
  # the cluster's document asserted a strategy nothing had chosen.
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

  # A unit that holds a value this cluster was handed from outside promises
  # hostnames that are routed where the thing actually runs, so asking this
  # cluster to route one is asking the wrong cluster. They were invisible here
  # until a crossing value became an ordinary unit, which is the one place
  # that change is visible outside the linker.
  #
  # Derived rather than passed: a unit that provides something and installs
  # nothing is not installing whatever answers for the hostname, which is the
  # whole of what "carried" meant. It used to be a list of the crossing units,
  # handed in from the module — so a lab-scope floe linked in some other way,
  # or a floe like `kapp` that answers a signature and renders nothing, was
  # outside the list and asked to route what it does not run.
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

  # A component inside an inclusion does not reach the cluster directly: its
  # hole resolves to the unit the inclusion injected to carry the value inward,
  # and an edge to one of those is dropped by the linker because the value is
  # the parent's. So the question is asked of whatever holds the unit — the
  # inclusion declared `requires.cluster` and a hole nothing inside reads is
  # refused, so an inclusion that reaches a cluster is one whose units have
  # one.
  #
  # The residue: a unit inside an inclusion that renders bundles and requires
  # no cluster is covered by a sibling that does. The statement one level up is
  # the true one, and the alternative is per-member attribution of a parent's
  # value, which is exactly what the linker declines to invent.
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
