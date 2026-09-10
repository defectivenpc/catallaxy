# bundles + link edges -> cluster metadata.
{ lib }:

let
  componentLib = import ./component.nix {
    inherit lib;
    floe = import ../floe-core { inherit lib; };
  };

  waitUtil = import ../kubernetes/wait.nix { inherit lib; };
  manifestGraph = import ../eval/manifest-graph.nix { inherit lib; };
  autoedges = import ../eval/manifest-autoedges.nix { inherit lib; };
  inherit (import ../eval/secret-refs.nix { inherit lib; }) secretAddress;

  # The aggregate bundle every `createNamespaces` resolves to, so two bundles
  # that both name a namespace do not end up waiting on each other.
  namespaceAggregate = "namespaces";

  projectionPrefix = "projection/";

  # Namespaces every cluster already has. A resource in one of these is not
  # missing a creator.
  builtinNamespaces = [
    "default"
    "kube-system"
    "kube-public"
    "kube-node-lease"
  ];

  namespacesNamedBy =
    bundle:
    lib.unique (
      lib.filter (n: n != null) (
        map (r: r.metadata.namespace or null) (lib.attrValues bundle.resources)
        ++ map (h: h.namespace) (lib.attrValues bundle.helmCharts)
      )
    );

  resolveOwner = defaultOwner: b: {
    bootstrap = if b.owner.bootstrap != null then b.owner.bootstrap else defaultOwner.bootstrap;
    steady = if b.owner.steady != null then b.owner.steady else defaultOwner.steady;
  };
in
{
  inherit namespaceAggregate projectionPrefix builtinNamespaces;

  # elaborateCluster :: { linkResult; coreKinds; defaultOwner } -> clusterMetadata
  elaborateCluster =
    {
      linkResult,
      coreKinds ? { },

      projectedSecrets ? { },

      extraBundles ? { },

      defaultOwner ? {
        bootstrap = "install-target";
        steady = "imperative";
      },
    }:
    let
      components = linkResult.out."catallaxy.component" or { };

      # ---- 1. join ---------------------------------------------------------

      joined = componentLib.joinAll (
        lib.mapAttrsToList (unit: c: componentLib.qualify unit c) components
      );

      bundles = joined.bundles // extraBundles;
      backs = joined.backs;

      # ---- 2. cross-floe edges --------------------------------------------

      bundlesOfUnit = unit: lib.attrNames (lib.filterAttrs (_: b: b.declaredBy == unit) joined.bundles);

      upstreamOf =
        unit:
        let
          holes =
            (linkResult.wiring.one.${unit} or { })
            // lib.filterAttrs (_: p: p != null) (linkResult.wiring.optional.${unit} or { });
        in
        lib.sort (a: b: a < b) (
          lib.unique (
            lib.concatLists (
              lib.mapAttrsToList (_hole: p: backs."${p.unit}/${p.instance}" or (bundlesOfUnit p.unit)) holes
            )
          )
        );

      withCrossFloeEdges = lib.mapAttrs (
        _name: b:
        b
        // {
          requires = map (n: "bundle:${n}") (lib.filter (n: !(lib.elem n b.needs)) (upstreamOf b.declaredBy));
        }
      ) bundles;

      # ---- 3. lower onto the graph's vocabulary ---------------------------

      probeOf =
        name: b:
        if b.ready == null then
          null
        else
          let
            missing = waitUtil.missingFields b.ready;
          in
          if waitUtil.conditionOnConditionless b.ready != "" then
            throw "bundle '${name}': ${waitUtil.conditionOnConditionless b.ready}"
          else if missing != [ ] then
            throw ''
              bundle '${name}' has a `ready` probe of kind '${b.ready.kind or "?"}' with no ${lib.concatStringsSep " or " missing}.

              The wait renders with an empty argument, which does not fail: it
              waits on a resource whose name is the empty string until the
              timeout, and reports the bundle as never becoming ready.
            ''
          else
            b.ready;

      expandSecretWildcards = lib.concatMap (
        s:
        let
          parts = lib.splitString "/" s;
        in
        if lib.head parts == "*" then
          map (ns: "${ns}/${lib.concatStringsSep "/" (lib.tail parts)}") known
        else
          [ s ]
      );

      rawBundles = lib.mapAttrs (name: b: {
        requires = map (n: "bundle:${n}") b.needs ++ b.requires;
        after = [ ];
        provides = map (k: "kind:${k}") b.crds;
        conflicts = [ ];

        inherit (b)
          resources
          createNamespaces
          declaredBy
          awaitRollout
          needsSecrets
          ;

        secrets = expandSecretWildcards b.secrets;
        externalSecrets = expandSecretWildcards b.externalSecrets;

        helmCharts = lib.mapAttrs (_: h: { inherit (h) namespace; }) b.helmCharts;

        kinds = lib.unique (lib.mapAttrsToList (_: r: r.kind or "") b.resources);
        resourceCount = lib.length (lib.attrNames b.resources);
        hasReadyProbe = b.ready != null;
        readyProbe = probeOf name b;
      }) withCrossFloeEdges;

      hasNamespaceContent = lib.any (b: b.createNamespaces != [ ]) (lib.attrValues bundles);

      namespacesBundle = lib.optionalAttrs hasNamespaceContent {
        ${namespaceAggregate} = {
          requires = [ ];
          after = [ ];
          provides = [ ];
          conflicts = [ ];
          resources = { };
          helmCharts = { };
          createNamespaces = [ ];
          declaredBy = "cluster";
          awaitRollout = true;
          kinds = [ ];
          resourceCount = 0;
          hasReadyProbe = false;
          readyProbe = null;
          secrets = [ ];
          needsSecrets = [ ];
          externalSecrets = [ ];
          routedHosts = [ ];
        };
      };

      projectionsBundle = lib.mapAttrs' (
        name: namespace:
        lib.nameValuePair "${projectionPrefix}${name}" {
          requires = [ ];

          after = [ "optional:namespace:${namespace}" ];
          provides = [ ];
          conflicts = [ ];
          resources = { };
          helmCharts = { };
          createNamespaces = [ ];
          declaredBy = "cluster";
          awaitRollout = true;
          kinds = [ ];
          resourceCount = 0;
          hasReadyProbe = false;
          readyProbe = null;
          secrets = [ (secretAddress namespace name) ];
          needsSecrets = [ ];
          externalSecrets = [ ];
          routedHosts = [ ];
        }
      ) projectedSecrets;

      graphBundles = autoedges.deriveAutoEdges {
        bundles = rawBundles // namespacesBundle // projectionsBundle;
        namespaceAggregate = if hasNamespaceContent then namespaceAggregate else null;
        inherit coreKinds;
      };

      waves = manifestGraph.computeWaves { bundles = graphBundles; };

      # ---- 4. lift the operator surface -----------------------------------

      liftChannel =
        channel:
        lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (
            name: b: lib.mapAttrs' (k: v: lib.nameValuePair "${name}/${k}" v) b.${channel}
          ) bundles
        );

      checkRunnable =
        bundle: category: n: v:
        let
          hasCommand = v.command != [ ];
          hasPackage = v.package != null;
        in
        if hasCommand && hasPackage then
          throw "ops command '${category} ${n}' on bundle '${bundle}' sets both `command` and `package`; set one"
        else if !hasCommand && !hasPackage then
          throw "ops command '${category} ${n}' on bundle '${bundle}' sets neither `command` nor `package`, so there is nothing to run"
        else
          v;

      opsPrefix =
        name:
        let
          parts = lib.splitString "/" name;
        in
        if lib.length parts == 2 && lib.head parts == lib.last parts then
          lib.head parts
        else
          lib.replaceStrings [ "/" ] [ "-" ] name;

      ops = lib.zipAttrsWith (_category: perBundle: lib.foldl' lib.mergeAttrs { } perBundle) (
        lib.mapAttrsToList (
          name: b:
          lib.mapAttrs (
            category:
            lib.mapAttrs' (n: v: lib.nameValuePair "${opsPrefix name}-${n}" (checkRunnable name category n v))
          ) b.ops
        ) bundles
      );

      # ---- 5. namespaces ---------------------------------------------------

      created = lib.unique (lib.concatMap (b: b.createNamespaces) (lib.attrValues bundles));

      known = created ++ builtinNamespaces;

      orphaned = lib.concatLists (
        lib.mapAttrsToList (
          name: b:
          map (ns: "bundle '${name}' installs into namespace '${ns}', which no bundle creates") (
            lib.filter (ns: !(lib.elem ns known)) (namespacesNamedBy b)
          )
        ) bundles
      );

      # ---- secrets ---------------------------------------------------------

      secretsMade = lib.unique (
        lib.mapAttrsToList (name: namespace: secretAddress namespace name) projectedSecrets
        ++ lib.concatMap (b: expandSecretWildcards (autoedges.secretsMadeBy b)) (
          lib.attrValues withCrossFloeEdges
        )
      );

      danglingSecrets = lib.concatLists (
        lib.mapAttrsToList (
          name: b:
          map (s: "bundle '${name}' reads Secret '${s}', which nothing in this cluster creates") (
            lib.filter (s: !(lib.elem s secretsMade)) (autoedges.secretsReadBy b)
          )
        ) withCrossFloeEdges
      );

      # ---- exposed hosts ---------------------------------------------------

      routeKinds = [
        "HTTPRoute"
        "TLSRoute"
      ];

      routePaths =
        r:
        lib.unique (
          lib.concatMap (
            rule:
            lib.concatMap (m: lib.optional ((m.path.value or "") != "") m.path.value) (rule.matches or [ ])
          ) (r.spec.rules or [ ])
        );

      exposedHosts =
        lib.concatLists (
          lib.mapAttrsToList (
            name: b:
            lib.concatMap (
              r:
              if lib.elem (r.kind or "") routeKinds then
                map (host: {
                  inherit host;
                  namespace = r.metadata.namespace or "default";
                  bundle = name;
                  tier = "public";
                  paths = routePaths r;
                }) (lib.filter (h: !(lib.hasInfix "*" h)) (r.spec.hostnames or [ ]))
              else
                [ ]
            ) (lib.attrValues b.resources)
          ) bundles
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (
            name: b:
            map (host: {
              inherit host;
              bundle = name;
              namespace = "default";
              tier = "public";
              paths = [ "/" ];
            }) b.routedHosts
          ) bundles
        );
    in
    if orphaned != [ ] then
      throw ''
        cluster elaboration: ${toString (lib.length orphaned)} namespace(s) with no creator.

        ${lib.concatStringsSep "\n        " orphaned}

        No single floe can answer this: the floe that creates a namespace and
        the floe that installs into it are usually different ones, so the
        check only exists once their components are joined. Add the namespace
        to some bundle's `createNamespaces`, or install into one the cluster
        already has (${lib.concatStringsSep ", " builtinNamespaces}).
      ''
    else if danglingSecrets != [ ] then
      throw ''
        cluster elaboration: ${toString (lib.length danglingSecrets)} Secret(s) with no creator.

        ${lib.concatStringsSep "\n        " danglingSecrets}

        A Secret that nothing creates is not a missing edge, it is a workload
        that will never start, and nothing before apply says so. The floe that
        reads one is rarely the floe that makes it, so this is only answerable
        once the components are joined.

        Whichever is true, say it on the bundle:
          `secrets`         — a chart or a controller here makes it, and eval
                              cannot see that.
          `externalSecrets` — it arrives from outside the manifests: a plan
                              step, an operator, or a human.
          `needsSecrets`    — the reference is real and some other floe or a
                              projection should be supplying it.
      ''
    else
      {
        inherit
          bundles
          backs
          waves
          exposedHosts
          ops
          ;

        graphBundles = graphBundles;
        namespaces = created;

        runtimeMaterialised = lib.unique (lib.concatMap (b: b.externalSecrets) (lib.attrValues bundles));
        lint = liftChannel "lint";
        verify = liftChannel "verify";

        inherit (joined)
          network
          steps
          imagesComplete
          assertions
          warnings
          drift
          ;

        images = lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (
            name: b: lib.mapAttrs' (k: v: lib.nameValuePair "${name}/${k}" v) b.images
          ) bundles
        );

        owners = lib.mapAttrs (_: resolveOwner defaultOwner) bundles;

        cluster = linkResult.out."catallaxy.cluster" or { };

        resources = linkResult.out."catallaxy.resources" or { };
        publications = linkResult.out."catallaxy.publications" or { };
      };
}
