# link: resolve holes by signature name, tie the graph with lib.fix, seal
# provides against signatures, collect outputs by kind, scan for deferred
# tokens to derive deploy edges and phases, then run policies.
{
  lib,
  types,
  floeLib,
}:

{
  link =
    {
      units,
      policies ? [ ],

      # Provides resolved outside this link, as `<name> -> { sig; value; origin; }`.
      #
      # A link is one graph, and a deployment is often more than one — two
      # clusters in a lab, each linked on its own, where a floe in the second
      # legitimately depends on something the first provides. Without this the
      # only way to express that is for the consumer to rebuild the producer's
      # value from a naming convention, which is a dependency with nothing
      # checking it.
      #
      # `sig` is what the value claims to satisfy, and it is sealed here like
      # any other provide: a value crossing a boundary is exactly where a
      # wrong shape is least likely to be noticed. `origin` is opaque to core
      # and travels only so an error can say where the value came from.
      #
      # What an external provider does *not* do is create an ordering edge.
      # There is no node in this graph to order against, and the thing it
      # names is applied by a different pass entirely — so `wiring.one` and
      # `wiring.optional` stay unit-only, and externals are reported
      # separately in `wiring.external`.
      external ? { },
    }:
    let
      unitNames = lib.attrNames units;
      externalNames = lib.attrNames external;

      isExternal = p: p ? external;

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

      providersOf =
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
        ) unitNames
        ++ lib.concatMap (
          n: lib.optional (external.${n}.sig.name == sigName) { external = n; }
        ) externalNames;

      describeProviders =
        ps:
        lib.concatMapStringsSep ", " (
          p:
          if isExternal p then
            "'${p.external}' (from outside this link${
              lib.optionalString (external.${p.external} ? origin) ": ${external.${p.external}.origin}"
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
                ) (lib.filter (p: !(isExternal p) && p.unit == u) (providersOf sig.name))
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
      localOnly = lib.filterAttrs (_hole: p: p != null && !(isExternal p));
      externalOnly = lib.filterAttrs (_hole: p: p != null && isExternal p);

      # ---- Evaluation fixpoint ---------------------------------------------

      sealSig =
        path: sig: v:
        types.checkValue path {
          tag = "record";
          fields = sig.fields;
          name = "signature ${sig.name}";
        } v;

      # An external provide, sealed against the signature it claims. Sealed
      # here rather than trusted from the caller: whoever assembled it did so
      # outside this link, which is the least likely place for a wrong shape
      # to be noticed, and a link that accepted one would hand it to a body
      # that reads a field which is not there.
      sealedExternal = lib.mapAttrs (n: entry: sealSig [ "external" n ] entry.sig entry.value) external;

      # A promise that was never meant to leave its own graph.
      #
      # Checked eagerly rather than where the value is read: an external of
      # the wrong signature usually resolves a hole *successfully* and hands
      # over an address that resolves nowhere, so there is no later point at
      # which anything notices.
      uncrossable = lib.filter (n: !(external.${n}.sig.crossCluster or false)) externalNames;

      fixed = lib.fix (
        self:
        lib.genAttrs unitNames (
          u:
          let
            inst = getInstance u;

            valueOf =
              p:
              if isExternal p then sealedExternal.${p.external} else self.${p.unit}.sealedProvides.${p.instance};

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

      # Only holes that resolved *inside* this link. An external provider is
      # not a node here, and what backs it is applied by a different pass —
      # so there is nothing in this graph for an edge to point at.
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
        # resolved from outside is in `external` instead, and is absent from
        # these two — which is what keeps every existing reader correct
        # without knowing externals exist: they all walk these to derive
        # order, and there is no order to derive against another graph.
        wiring = {
          one = lib.mapAttrs (_u: localOnly) wiringOne;
          optional = lib.mapAttrs (_u: localOnly) wiringOptional;

          external = lib.mapAttrs (
            u: _: (externalOnly wiringOne.${u}) // (externalOnly wiringOptional.${u})
          ) (lib.genAttrs unitNames getInstance);
        };
      };

      violations = lib.concatMap (p: p result) policies;
    in
    # Before the policies, because this is core's own invariant rather than a
    # distribution's rule, and because a self-resolved hole makes every policy
    # downstream reason about a link that should not exist.
    if uncrossable != [ ] then
      throw (
        "floe link error: these provides were offered to this link from outside it, and "
        + "their signatures do not cross a link boundary:\n  - "
        + lib.concatMapStringsSep "\n  - " (
          n:
          "'${n}' (signature '${external.${n}.sig.name}'"
          + lib.optionalString (external.${n} ? origin) ", from ${external.${n}.origin}"
          + ")"
        ) uncrossable
        + "\n\nA signature carries `crossCluster = true` when what it promises is still "
        + "true for a consumer somewhere else — a routed address, an issuer, a registry. "
        + "Most promise that something is running *here*, and resolving one of those from "
        + "another graph yields a value that reads correctly and describes a controller "
        + "that is not present."
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
