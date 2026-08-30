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

  # A Secret the lab projects gets a bundle that renders nothing and provides
  # it, so a consumer's `secret:` edge resolves against something in the
  # graph. The prefix is a CLI contract, not a naming choice: `cata` finds the
  # projections to inject by scanning wave keys for it.
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

      # Secrets the lab lands in this cluster from its own stores, as
      # `<projection name> -> <namespace>`. The projection's name is the
      # Secret's name; `inject_projections` renders `metadata.name` from it.
      #
      # One pseudo-bundle each, not one aggregate: the CLI finds the work by
      # scanning the wave layout for bundles keyed `projection/<name>`
      # (`cli/src/io/ssa/mod.rs:212`) and injects each at the wave it appears
      # in. An aggregate matches nothing and silently applies no Secret.
      projectedSecrets ? { },

      # Bundles the lab owns rather than any floe. Cross-cluster secret
      # sharing is the case this exists for: which cluster publishes what and
      # who subscribes is wiring *between* clusters, which a floe-core link
      # cannot express because it only ever sees one cluster's units.
      #
      # Bundle-shaped, and joined before the cross-floe pass, so they get the
      # same derived edges and the same coherence checks as anything a floe
      # contributed. `declaredBy = "cluster"` is what keeps them out of the
      # per-floe ordering lookup.
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
      #
      # A consumer never names a producer's bundle. The linker knows A
      # resolved hole `h` to B's provide `i`; `backs."B/i"` says which of B's
      # bundles have to be ready before that promise is good. With no `backs`
      # entry the answer is all of them: coarse, but correct, and a floe that
      # never writes `backs` still orders.

      # Over the joined bundles, not `bundles`: only a floe's bundles belong
      # to a unit. Lab-owned bundles carry `declaredBy = "cluster"` as the
      # "no floe wrote this" sentinel, and a lab is free to *name* a unit
      # `cluster` — the example labs do, for the k3d floe. Reading the merged
      # set here handed every floe requiring KUBERNETES_CLUSTER an upstream
      # edge to every lab-owned bundle, and the lab bundles depend on the
      # floes, so the whole graph became one cycle.
      bundlesOfUnit = unit: lib.attrNames (lib.filterAttrs (_: b: b.declaredBy == unit) joined.bundles);

      # unit -> the qualified bundle names its requirements must follow.
      #
      # Exactly-one holes only. A fan-in hole runs the other way: the
      # collector is what has to exist before the collected attach to it, so
      # ordering a gateway after its own routes would be backwards, and a
      # cycle wherever the routes also depend on the gateway — which they
      # always do, because that is what they attach to.
      upstreamOf =
        unit:
        lib.unique (
          lib.concatLists (
            lib.mapAttrsToList (
              _hole: p:
              if p.unit == unit then
                [ ] # a floe resolving its own provide orders nothing
              else
                backs."${p.unit}/${p.instance}" or (bundlesOfUnit p.unit)
            ) (linkResult.wiring.one.${unit} or { })
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

      # `*/<name>` means every namespace this cluster has. Expanded here
      # because the namespace set is a fact the cluster holds and the floe
      # that declared the wildcard does not — a trust-manager Bundle with an
      # empty `namespaceSelector` genuinely cannot name them.
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
        };
      };

      projectionsBundle = lib.mapAttrs' (
        name: namespace:
        lib.nameValuePair "${projectionPrefix}${name}" {
          requires = [ ];

          # The Secret has to land after the namespace holding it exists, and
          # before anything reading it. The first is an edge; the second falls
          # out of the `secret:` token below.
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
          secrets = [ "${namespace}/${name}" ];
          needsSecrets = [ ];
          externalSecrets = [ ];
        }
      ) projectedSecrets;

      graphBundles = autoedges.deriveAutoEdges {
        bundles = rawBundles // namespacesBundle // projectionsBundle;
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
      # `command` and `package` are the two ways to say what runs, and a
      # command with neither is dispatchable but unrunnable: the generated
      # tool would match the branch and `exec` nothing. Checked here rather
      # than in the renderer because every cluster elaborates and only a lab
      # with ops renders, so a floe with a malformed command would otherwise
      # go unnoticed until something happened to use it.
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

      # `<unit>/<bundle>` with a dash for the slash, which an argv position
      # would not carry. A floe whose only bundle is named after itself —
      # velero, and most single-bundle floes — would otherwise reach the
      # operator as `velero-velero-create`, and this is the one surface where
      # the name is something a person types.
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
      #
      # Same shape of problem as a namespace with no creator, same place to
      # catch it. A floe reading a Secret is usually not the floe that makes
      # one, so this is only answerable once the components are joined.

      secretsMade = lib.unique (
        lib.mapAttrsToList (name: namespace: "${namespace}/${name}") projectedSecrets
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

        # Secrets that reach the cluster from outside the manifest stream.
        # `cata lab lint`'s dangling-reference rule takes its escape hatch
        # from this, so the CLI and the elaborator agree on what is allowed to
        # be missing rather than each keeping its own list.
        runtimeMaterialised = lib.unique (lib.concatMap (b: b.externalSecrets) (lib.attrValues bundles));
        lint = liftChannel "lint";
        verify = liftChannel "verify";

        # Per-floe facts, keyed by unit rather than merged: two floes' netpol
        # declarations are two declarations, and the policy synthesiser reads
        # them side by side.
        inherit (joined)
          network
          steps
          imagesComplete
          assertions
          warnings
          drift
          ;

        # A floe that says nothing about its network is not the same as one
        # that needs nothing, and the difference is why `declared` exists.
        # Naming them is all this does; refusing them is a lab's decision.
        undeclaredNetwork = lib.attrNames (lib.filterAttrs (_: n: !(n.declared or false)) joined.network);

        images = lib.foldl' lib.mergeAttrs { } (
          lib.mapAttrsToList (
            name: b: lib.mapAttrs' (k: v: lib.nameValuePair "${name}/${k}" v) b.images
          ) bundles
        );

        owners = lib.mapAttrs (_: resolveOwner defaultOwner) bundles;

        cluster = linkResult.out."catallaxy.cluster" or { };
      };
}
