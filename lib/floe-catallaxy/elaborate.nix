# bundles + link edges -> cluster metadata.
#
# Core collects outputs keyed by unit and does not merge them, which is what
# keeps the linker domain-agnostic. A cluster is not a pile of units, so the
# join belongs here, in the domain. Another domain joins differently.
{ lib }:

let
  componentLib = import ./component.nix {
    inherit lib;
    floe = import ../floe-core { inherit lib; };
  };

  waitUtil = import ../util/wait.nix { inherit lib; };
  manifestGraph = import ../eval/manifest-graph.nix { inherit lib; };
  autoedges = import ../eval/manifest-autoedges.nix { inherit lib; };

  # The aggregate bundle every `createNamespaces` resolves to, so two bundles
  # that both name a namespace do not end up waiting on each other.
  namespaceAggregate = "namespaces";

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
  inherit namespaceAggregate builtinNamespaces;

  # elaborateCluster :: { linkResult; coreKinds; defaultOwner } -> clusterMetadata
  elaborateCluster =
    {
      linkResult,
      coreKinds ? { },
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

      bundles = joined.bundles;
      backs = joined.backs;

      # ---- 2. cross-floe edges --------------------------------------------
      #
      # A consumer never names a producer's bundle. The linker knows A
      # resolved hole `h` to B's provide `i`; `backs."B/i"` says which of B's
      # bundles have to be ready before that promise is good. With no `backs`
      # entry the answer is all of them: coarse, but correct, and a floe that
      # never writes `backs` still orders.

      bundlesOfUnit = unit: lib.attrNames (lib.filterAttrs (_: b: b.declaredBy == unit) bundles);

      # unit -> the qualified bundle names its requirements must follow
      upstreamOf =
        unit:
        lib.unique (
          lib.concatLists (
            lib.concatLists (
              lib.mapAttrsToList (
                _hole: providers:
                map (
                  p:
                  if p.unit == unit then
                    [ ] # a floe resolving its own provide orders nothing
                  else
                    backs."${p.unit}/${p.instance}" or (bundlesOfUnit p.unit)
                ) providers
              ) (linkResult.wiring.${unit} or { })
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
      #
      # `manifest-graph.nix` and `manifest-autoedges.nix` read a token
      # vocabulary. `needs` and the derived cross-floe edges lower onto it,
      # which is why both files are reused unchanged rather than reimplemented.

      probeOf =
        name: b:
        if b.ready == null then
          null
        else
          let
            missing = waitUtil.missingFields b.ready;
          in
          if missing != [ ] then
            throw ''
              bundle '${name}' has a `ready` probe of kind '${b.ready.kind or "?"}' with no ${lib.concatStringsSep " or " missing}.

              The wait renders with an empty argument, which does not fail: it
              waits on a resource whose name is the empty string until the
              timeout, and reports the bundle as never becoming ready.
            ''
          else
            b.ready;

      rawBundles = lib.mapAttrs (name: b: {
        # `needs` is intra-floe and already qualified; requires is `READY`,
        # after is sequence-only. A sibling this bundle names must be ready,
        # not merely applied, so both land in `requires`.
        requires = map (n: "bundle:${n}") b.needs ++ b.requires;
        after = [ ];
        provides = map (k: "kind:${k}") b.crds;
        conflicts = [ ];

        inherit (b)
          resources
          createNamespaces
          declaredBy
          awaitRollout
          ;

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
        };
      };

      graphBundles = autoedges.deriveAutoEdges {
        bundles = rawBundles // namespacesBundle;
        namespaceAggregate = if hasNamespaceContent then namespaceAggregate else null;
        inherit coreKinds;
      };

      waves = manifestGraph.computeWaves { bundles = graphBundles; };

      # ---- 4. lift the operator surface -----------------------------------
      #
      # Written on the bundle for locality, read at the cluster. The key is
      # already unit-qualified, so two floes cannot collide.

      liftChannel =
        channel:
        lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (
            name: b: lib.mapAttrs' (k: v: lib.nameValuePair "${name}/${k}" v) b.${channel}
          ) bundles
        );

      # Ops are keyed category-then-name, and the invocation is
      # `<lab>-ops <category> <name>`, so the category has to survive the lift
      # and the qualifier goes on the name. A slash would not survive an
      # argv position, so it becomes a dash.
      ops = lib.zipAttrsWith (_category: perBundle: lib.foldl' lib.mergeAttrs { } perBundle) (
        lib.mapAttrsToList (
          name: b:
          lib.mapAttrs (
            _category:
            lib.mapAttrs' (n: v: lib.nameValuePair "${lib.replaceStrings [ "/" ] [ "-" ] name}-${n}" v)
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

      # ---- exposed hosts ---------------------------------------------------

      routeKinds = [
        "HTTPRoute"
        "TLSRoute"
      ];

      # A record per hostname, not a bare string: `cata lab verify` probes
      # these, and a failing probe has to be able to name the bundle that
      # declared the route. `paths` matters too — probing `/` on a host whose
      # route only matches `/api` proves nothing, and the gateway is right to
      # refuse it.
      routePaths =
        r:
        lib.unique (
          lib.concatMap (
            rule:
            lib.concatMap (m: lib.optional ((m.path.value or "") != "") m.path.value) (rule.matches or [ ])
          ) (r.spec.rules or [ ])
        );

      exposedHosts = lib.concatLists (
        lib.mapAttrsToList (
          name: b:
          lib.concatMap (
            r:
            if lib.elem (r.kind or "") routeKinds then
              map (host: {
                inherit host;
                namespace = r.metadata.namespace or "default";
                bundle = name;
                # Every route is public until there is an internal tier to
                # put one behind. Saying "public" when we cannot tell would
                # be a lie; there is currently only one tier.
                tier = "public";
                paths = routePaths r;
              }) (lib.filter (h: !(lib.hasInfix "*" h)) (r.spec.hostnames or [ ]))
            else
              [ ]
          ) (lib.attrValues b.resources)
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
        lint = liftChannel "lint";
        verify = liftChannel "verify";

        images = lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (
            name: b: lib.mapAttrs' (k: v: lib.nameValuePair "${name}/${k}" v) b.images
          ) bundles
        );

        owners = lib.mapAttrs (_: resolveOwner defaultOwner) bundles;

        cluster = linkResult.out."catallaxy.cluster" or { };
      };
}
