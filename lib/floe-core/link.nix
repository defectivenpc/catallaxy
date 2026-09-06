# link: resolve holes by signature name, tie the graph with lib.fix, seal
# provides against signatures, collect outputs by kind, scan for deferred
# tokens to derive deploy edges and phases, then run policies.
{
  lib,
  types,
  interfaces,
  floeLib,
}:

{
  link =
    {
      units,
      policies ? [ ],

      # The enclosing scope: provides from a link that contains this one, as
      # `<name> -> { sig; value; origin; }`, already sealed there.
      #
      # A link is one graph and a deployment is often several nested ones — a
      # lab holding clusters, each linked on its own. Something offered by the
      # lab is in scope for every cluster in it, and a floe that needs it says
      # so with an ordinary `requires` rather than rebuilding the value from a
      # naming convention.
      #
      # **A local provider shadows one from scope.** The scope is consulted
      # only when no unit of this link provides the signature, which is what
      # every scoped language does and what makes a lab-wide offer safe: a
      # cluster with its own gateway keeps it, and one without picks up the
      # lab's. Treating the two as competing providers refuses exactly the
      # arrangement the scope exists to allow.
      #
      # `sig` is what the value claims to satisfy and is sealed here again: a
      # value crossing a boundary is where a wrong shape is least likely to be
      # noticed. `origin` is opaque to core and travels only so an error can
      # say where the value came from.
      #
      # What a scope provider does *not* do is create an ordering edge. There
      # is no node in this graph to order against and what backs it is applied
      # by a different pass, so `wiring.one` and `wiring.optional` stay
      # unit-only and scope resolutions are reported in `wiring.scope`.
      scope ? { },
    }:
    let
      unitNames = lib.attrNames units;
      scopeNames = lib.attrNames scope;

      isFromScope = p: p ? scope;

      getInstance =
        u:
        let
          inst = units.${u};
        in
        if inst.__floeInstance or false then
          inst
        else
          throw "floe link error: unit '${u}' is not an instantiated floe (call .instantiate { ... } on it)";

      # ---- Resolution (headers only; no body evaluation) -------------------

      localProvidersOf =
        sigName:
        lib.concatMap (
          u:
          let
            provs = (getInstance u).def.provides;
          in
          lib.concatMap (
            instName:
            lib.optional (provs.${instName}.name == sigName) {
              unit = u;
              instance = instName;
            }
          ) (lib.attrNames provs)
        ) unitNames;

      scopeProvidersOf =
        sigName: lib.concatMap (n: lib.optional (scope.${n}.sig.name == sigName) { scope = n; }) scopeNames;

      # Nearer wins. The enclosing scope is asked only when nothing here
      # answers, so a local provider shadows one from outside rather than
      # colliding with it.
      providersOf =
        sigName:
        let
          here = localProvidersOf sigName;
        in
        if here != [ ] then here else scopeProvidersOf sigName;

      describeProviders =
        ps:
        lib.concatMapStringsSep ", " (
          p:
          if isFromScope p then
            "'${p.scope}' (from the enclosing scope${
              lib.optionalString (scope.${p.scope} ? origin) ": ${scope.${p.scope}.origin}"
            })"
          else
            "'${p.unit}' (as ${p.instance})"
        ) ps;

      # A unit does not satisfy its own hole.
      #
      # `providersOf` scans every unit, the requester included, so a floe that
      # provides and requires one signature resolves to itself — no error, no
      # second provider to disambiguate against, just a value it hands itself.
      # The failures are quiet: an otel-collector providing TRACE_INGEST would
      # have exported into its own receiver, and the elaborator carries a
      # branch dropping the ordering edge for exactly this case, which is a
      # workaround for a shape nothing should produce.
      #
      # Computed over every hole rather than thrown from inside the resolution
      # — that is lazy, and a floe that declares the hole and never reads it
      # would link fine and fail later, if ever. This is an invariant of the
      # link, so it holds whether or not anything looks.
      #
      # Refused rather than filtered, because a floe wanting its own provide
      # already has it: it is `config.floe.provides.<name>`, in scope, with no
      # link involved.
      selfResolutions = lib.concatMap (
        u:
        let
          inst = getInstance u;
          holesOf =
            label: decl:
            lib.concatLists (
              lib.mapAttrsToList (
                hole: sig:
                map (
                  p: "unit '${u}' ${label} '${sig.name}' as hole '${hole}' and also provides it (as ${p.instance})"
                ) (lib.filter (p: !(isFromScope p) && p.unit == u) (localProvidersOf sig.name))
              ) decl
            );
        in
        holesOf "requires" inst.def.requires ++ holesOf "optionally requires" inst.def.requiresOptional
      ) unitNames;

      wiringOne = lib.mapAttrs (
        u: inst:
        lib.mapAttrs (
          hole: sig:
          let
            ps = providersOf sig.name;
          in
          if ps == [ ] then
            throw (
              "floe link error: no provider for signature '${sig.name}' "
              + "(required by unit '${u}' as hole '${hole}'). "
              + "Units in this link: ${lib.concatStringsSep ", " unitNames}"
            )
          else if lib.length ps > 1 then
            throw (
              "floe link error: signature '${sig.name}' (required by unit "
              + "'${u}' as hole '${hole}') is provided by multiple units: "
              + "${describeProviders ps}. Remove one or split the deployment."
            )
          else
            lib.head ps
        ) inst.def.requires
      ) (lib.genAttrs unitNames getInstance);

      # Same refusal as `wiringOne` for two providers, and `null` rather than
      # a throw for none. The difference from `requires` is only that zero is
      # allowed; everything else about it — sealing, ordering — is identical,
      # which is the point.
      wiringOptional = lib.mapAttrs (
        u: inst:
        lib.mapAttrs (
          hole: sig:
          let
            ps = providersOf sig.name;
          in
          if lib.length ps > 1 then
            throw (
              "floe link error: signature '${sig.name}' (optionally required by "
              + "unit '${u}' as hole '${hole}') is provided by multiple units: "
              + "${describeProviders ps}. Remove one or split the deployment."
            )
          else
            (if ps == [ ] then null else lib.head ps)
        ) inst.def.requiresOptional
      ) (lib.genAttrs unitNames getInstance);

      # Holes answered by a unit of this link, and holes answered from
      # outside. Everything that reasons about *order* wants the first;
      # everything that reasons about *what a floe got* wants both.
      localOnly = lib.filterAttrs (_hole: p: p != null && !(isFromScope p));
      fromScopeOnly = lib.filterAttrs (_hole: p: p != null && isFromScope p);

      # ---- Evaluation fixpoint ---------------------------------------------

      sealSig =
        path: sig: v:
        types.checkValue path {
          tag = "record";
          fields = sig.fields;
          name = "signature ${sig.name}";
        } v;

      # A provide from the enclosing scope, sealed against the signature it
      # claims. Sealed here rather than trusted from the caller: whoever
      # assembled it did so outside this link, which is the least likely place
      # for a wrong shape to be noticed, and a link that accepted one would
      # hand it to a body that reads a field which is not there.
      # Sealed like any other provide, and then narrowed to what still means
      # something here.
      #
      # A field typed `T.local` describes a place in the link that produced it
      # — a Service address, a namespace, a CRD installed there. Read from
      # here it is not wrong-looking, it is wrong: a string that resolves
      # nowhere, or a namespace in somebody else's cluster. So it is replaced
      # by a throw rather than checked, because there is no value that would
      # be correct.
      #
      # Lazily, which is the whole point of doing this per field: a consumer
      # that reads only the portable half of a signature is not doing anything
      # wrong and must not be refused. `OIDC_PROVIDER` is the case — from
      # another link you can validate a token against the issuer and you
      # cannot render a client, and both halves of that are true at once.
      sealedScope = lib.mapAttrs (
        n: entry:
        let
          sealed = sealSig [ "scope" n ] entry.sig entry.value;
        in
        lib.mapAttrs (
          field: value:
          if types.isLocal entry.sig.fields.${field} then
            throw (
              "floe link error: '${entry.sig.name}.${field}' is local to the link that "
              + "provided it${lib.optionalString (entry ? origin) " (${entry.origin})"}, and this "
              + "is a different one. It names something that exists there — a Service "
              + "address, a namespace, a CRD — and there is no value for it here.\n\n"
              + "Fields of '${entry.sig.name}' that do travel: "
              + (
                let
                  portable = lib.attrNames (lib.filterAttrs (_: t: !(types.isLocal t)) entry.sig.fields);
                in
                if portable == [ ] then "none." else lib.concatStringsSep ", " portable + "."
              )
            )
          else
            value
        ) sealed
      ) scope;

      # A promise with nothing portable in it at all.
      #
      # Derived rather than declared: if every field is local then every read
      # throws, and a hole "resolved" that way is one that resolves to nothing
      # usable. That is certainly a mistake, so it is refused up front rather
      # than at whichever field the consumer happens to touch first.
      #
      # This is what a per-signature flag was approximating, and it falls out
      # of the fields instead of being asserted beside them — so a signature
      # that gains a routed address starts crossing without anyone
      # remembering to say so.
      uncrossable = lib.filter (n: interfaces.isUncrossable scope.${n}.sig) scopeNames;

      fixed = lib.fix (
        self:
        lib.genAttrs unitNames (
          u:
          let
            inst = getInstance u;

            valueOf =
              p: if isFromScope p then sealedScope.${p.scope} else self.${p.unit}.sealedProvides.${p.instance};

            resolved =
              lib.mapAttrs (_hole: valueOf) wiringOne.${u}
              // lib.mapAttrs (_hole: p: if p == null then null else valueOf p) wiringOptional.${u};
          in
          rec {
            evaluated = floeLib.evalFloe {
              instance = inst;
              unitName = u;
              resolvedRequires = resolved;
            };
            sealedProvides = lib.mapAttrs (
              instName: sig:
              let
                v =
                  evaluated.config.floe.provides.${instName} or (throw (
                    "floe '${u}': declares provide '${instName}' (signature "
                    + "'${sig.name}') but its body never defines "
                    + "config.floe.provides.${instName}"
                  ));
              in
              sealSig [ u "provides" instName ] sig v
            ) inst.def.provides;
            outs = lib.mapAttrs (
              kName: kind:
              types.checkValue [ u "out" kName ] kind.schema (evaluated.config.floe.out.${kName} or { })
            ) inst.def.out;
          }
        )
      );

      # ---- Graph derivation ------------------------------------------------

      scanTokens =
        v:
        if types.isDeferredToken v then
          [ v ]
        else if builtins.isAttrs v then
          lib.concatMap scanTokens (lib.attrValues v)
        else if builtins.isList v then
          lib.concatMap scanTokens v
        else
          [ ];

      # Only holes that resolved *inside* this link. A provider from the
      # enclosing scope is not a node here, and what backs it is applied by a
      # different pass — so there is nothing in this graph to point an edge at.
      evalEdges = lib.concatMap (
        u:
        lib.mapAttrsToList (hole: p: {
          from = u;
          to = p.unit;
          via = hole;
          kind = "eval";
        }) (localOnly wiringOne.${u})
        ++ lib.concatLists (
          lib.mapAttrsToList (
            hole: p:
            lib.optional (p != null) {
              from = u;
              to = p.unit;
              via = hole;
              kind = "eval";
            }
          ) (localOnly wiringOptional.${u})
        )
      ) unitNames;

      deployEdges = lib.unique (
        lib.concatMap (
          u:
          lib.concatMap (
            tok:
            lib.optional (tok ? source && tok.source != u) {
              from = u;
              to = tok.source;
              via = lib.concatStringsSep "." (map toString (tok.path or [ ]));
              kind = "deploy";
            }
          ) (scanTokens fixed.${u}.outs)
        ) unitNames
      );

      deployDepsOf = u: lib.unique (map (e: e.to) (lib.filter (e: e.from == u) deployEdges));

      phaseOf =
        seen: u:
        if lib.elem u seen then
          throw ("floe link error: deferred-value cycle: " + lib.concatStringsSep " -> " (seen ++ [ u ]))
        else
          let
            deps = deployDepsOf u;
          in
          if deps == [ ] then 0 else 1 + lib.foldl' lib.max 0 (map (phaseOf (seen ++ [ u ])) deps);

      # ---- Output collection -----------------------------------------------

      allKindNames = lib.unique (
        lib.concatMap (
          u: map (k: (getInstance u).def.out.${k}.name) (lib.attrNames (getInstance u).def.out)
        ) unitNames
      );

      outByKind = lib.genAttrs allKindNames (
        kindName:
        lib.foldl' (
          acc: u:
          let
            matching = lib.filterAttrs (_: kind: kind.name == kindName) (getInstance u).def.out;
          in
          if matching == { } then
            acc
          else
            acc // { ${u} = fixed.${u}.outs.${lib.head (lib.attrNames matching)}; }
        ) { } unitNames
      );

      # ---- Result and policies ---------------------------------------------

      result = {
        provides = lib.genAttrs unitNames (u: fixed.${u}.sealedProvides);
        out = outByKind;
        graph = {
          nodes = unitNames;
          edges = evalEdges ++ deployEdges;
        };
        phases = lib.genAttrs unitNames (phaseOf [ ]);

        # What each hole resolved to, as `[ { unit; instance; } ]`. An eval
        # edge says A needed B; this says which of B's provides answered,
        # which is the only thing that can key a backend's "and therefore
        # wait for these parts of B" rule.
        #
        # Both kinds mean the same thing about order — A depends on B, so
        # whatever B promised has to be true before A can use it — and a
        # backend should treat them alike. They stay apart only because an
        # optional hole may be `null`, which is not a unit a backend can
        # order against.
        #
        # This used to say the opposite, of `requiresMany`: that a fan-in ran
        # the other way, because the gateway comes up and *then* routes attach
        # to it. That was true of the one fan-in there was and false in
        # general — a collector consuming its backends has to follow them —
        # and it cost the ordering edge for every case that was not routes.
        # `requiresOptional` has no such ambiguity.
        #
        # Both carry only holes a *unit of this link* answered. A hole
        # resolved from the enclosing scope is in `scope` instead, and absent
        # from these two — which is what keeps every existing reader correct
        # without knowing the scope exists: they all walk these to derive
        # order, and there is no order to derive against another graph.
        wiring = {
          one = lib.mapAttrs (_u: localOnly) wiringOne;
          optional = lib.mapAttrs (_u: localOnly) wiringOptional;

          scope = lib.mapAttrs (u: _: (fromScopeOnly wiringOne.${u}) // (fromScopeOnly wiringOptional.${u})) (
            lib.genAttrs unitNames getInstance
          );
        };
      };

      violations = lib.concatMap (p: p result) policies;
    in
    # Before the policies, because this is core's own invariant rather than a
    # distribution's rule, and because a self-resolved hole makes every policy
    # downstream reason about a link that should not exist.
    if uncrossable != [ ] then
      throw (
        "floe link error: these provides were offered to this link by its enclosing "
        + "scope, and every field of their signatures is link-local:\n  - "
        + lib.concatMapStringsSep "\n  - " (
          n:
          "'${n}' (signature '${scope.${n}.sig.name}'"
          + lib.optionalString (scope.${n} ? origin) ", from ${scope.${n}.origin}"
          + ")"
        ) uncrossable
        + "\n\nNothing in them would be readable here, so resolving a hole against one "
        + "leaves the consumer with a value it cannot use. These are the promises that "
        + "something is running *in a particular place* — a controller, a webhook, a "
        + "storage class — and the place is not this one."
      )
    else if selfResolutions != [ ] then
      throw (
        "floe link error: a unit does not satisfy its own hole.\n  - "
        + lib.concatStringsSep "\n  - " selfResolutions
        + "\n\nRead `config.floe.provides.<instance>` directly; it is in scope "
        + "and needs no link."
      )
    else if violations != [ ] then
      throw ("floe policy violation(s):\n  - " + lib.concatStringsSep "\n  - " violations)
    else
      result;
}
