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
    }:
    let
      unitNames = lib.attrNames units;

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
        ) unitNames;

      describeProviders = ps: lib.concatMapStringsSep ", " (p: "'${p.unit}' (as ${p.instance})") ps;

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

      # ---- Evaluation fixpoint ---------------------------------------------

      sealSig =
        path: sig: v:
        types.checkValue path {
          tag = "record";
          fields = sig.fields;
          name = "signature ${sig.name}";
        } v;

      fixed = lib.fix (
        self:
        lib.genAttrs unitNames (
          u:
          let
            inst = getInstance u;
            resolved =
              lib.mapAttrs (_hole: p: self.${p.unit}.sealedProvides.${p.instance}) wiringOne.${u}
              // lib.mapAttrs (
                _hole: p: if p == null then null else self.${p.unit}.sealedProvides.${p.instance}
              ) wiringOptional.${u};
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

      evalEdges = lib.concatMap (
        u:
        lib.mapAttrsToList (hole: p: {
          from = u;
          to = p.unit;
          via = hole;
          kind = "eval";
        }) wiringOne.${u}
        ++ lib.concatLists (
          lib.mapAttrsToList (
            hole: p:
            lib.optional (p != null) {
              from = u;
              to = p.unit;
              via = hole;
              kind = "eval";
            }
          ) wiringOptional.${u}
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
        wiring = {
          one = wiringOne;
          optional = wiringOptional;
        };
      };

      violations = lib.concatMap (p: p result) policies;
    in
    if violations != [ ] then
      throw ("floe policy violation(s):\n  - " + lib.concatStringsSep "\n  - " violations)
    else
      result;
}
