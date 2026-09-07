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

        inputs = lib.genAttrs unitNames (u: interfaces.renderInputs (getInstance u).def.inputs);

        graph = {
          nodes = unitNames;
          edges = evalEdges ++ deployEdges;
        };
        phases = lib.genAttrs unitNames (phaseOf [ ]);

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
