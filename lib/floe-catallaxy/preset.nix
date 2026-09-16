# A preset: a floe that includes floes.
#
# Backpack's unit inclusion, which floe core does not have and which every lab
# grew a hand-rolled stand-in for — `homelab`'s `platform = clusterName: {…}`
# and `self-edge`'s `common`, both closures in one file, invisible to anything
# that checks and uncopyable between labs.
#
# It is not a floe instance. RFC 0001 says an instance is one thing, and
# nothing here needs that to change: a preset is expanded into its members by
# whoever places it, before the linker sees a cluster at all. What it borrows
# from a floe is the *declaration* — `inputs` and `provides` — so a reader can
# see what a preset offers without reading its body, `floe-docs` can render it,
# and the declaration can be checked against the members rather than trusted.
#
# Expansion is flat and members keep their own keys. An app requiring
# `API_GATEWAY` has to see the gateway the preset installed, and
# `lab.clusters.<c>.provides` names a member as `<instName>/<provide>`, which a
# prefix would break. The cost is that a member can collide with something the
# cluster writes directly, which is refused by name rather than resolved.
{ lib, floe }:

rec {
  isPreset = v: (v.__floePreset or false) == true;

  # mkPreset :: { name; summary; inputs; provides; members } -> presetDef
  #
  # `members` is a function of the checked inputs returning instantiated floes,
  # exactly the attrset a lab would otherwise have written by hand.
  mkPreset =
    {
      name,
      summary,
      inputs ? { },
      provides ? { },
      members,
    }:
    let
      # Read off `supplied` rather than checked, because they hold floe
      # instances and `checkInputs` deep-forces. Declared below all the same,
      # so the generated interface still shows them.
      structural = [
        "provisioner"
        "overrides"
        "omit"
      ];

      declaredKnobs = removeAttrs inputs structural;

      # The two every preset has, so no preset writes them and every preset
      # answers to the same words.
      allInputs = inputs // {
        overrides = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
          description = ''
            Members to replace, keyed by the member's name. A replacement must
            provide what it replaces, which is checked — swapping a gateway for
            something that is not one is refused here rather than at whichever
            consumer resolved against it first.
          '';
        };

        omit = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Members to leave out, by name. Naming one the preset does not have
            is refused: a typo that silently omits nothing is how a preset
            becomes something people fork instead of parameterise.
          '';
        };
      };

      def = {
        __floePresetDef = true;
        inherit name summary provides;
        inputs = allInputs;

        instantiate =
          supplied:
          let
            # The knobs are checked by the same code a floe's inputs are —
            # a floe with no body, instantiated only to validate — rather than
            # by a second implementation that could drift from it.
            #
            # The three structural ones cannot go through it. `checkInputs`
            # deep-forces, which is what stops a derivation travelling as an
            # input, and a floe instance is caught by the same net: forcing
            # `provisioner` would force the provisioner's own inputs before
            # the lab has placed it and given it a name. So they are read off
            # `supplied` directly and validated here.
            knobs =
              (floe.mkFloe {
                inherit name summary;
                inputs = declaredKnobs;
              }).instantiate
                (removeAttrs supplied structural);

            inputs = knobs.inputsChecked // {
              provisioner =
                supplied.provisioner
                  or (throw "preset '${name}': needs a `provisioner` — a floe providing KUBERNETES_CLUSTER.");
              overrides = supplied.overrides or { };
              omit = supplied.omit or [ ];
            };

            declared = members inputs;

            unknownOmits = lib.filter (m: !(declared ? ${m})) inputs.omit;
            unknownOverrides = lib.filter (m: !(declared ? ${m})) (lib.attrNames inputs.overrides);

            kept = (removeAttrs declared inputs.omit) // inputs.overrides;

            # What the members actually provide, against what the preset says
            # it does. A declaration nobody checks is a comment: this is the
            # difference between a preset and a closure, so it is checked at
            # the moment the preset is instantiated rather than trusted.
            #
            # Declared must be a subset, not equal — a member providing more
            # than the preset advertises is ordinary, and forcing the preset
            # to list everything would make adding a member a breaking change.
            actual = lib.unique (
              lib.concatMap (i: map (s: s.name) (lib.attrValues (i.def.provides or { }))) (lib.attrValues kept)
            );

            claimed = lib.unique (map (s: s.name) (lib.attrValues provides));
            unmet = lib.filter (s: !(lib.elem s actual)) claimed;
          in
          if unknownOmits != [ ] then
            throw (
              "preset '${name}': `omit` names ${lib.concatStringsSep ", " unknownOmits}, "
              + "which it does not have. Members: ${lib.concatStringsSep ", " (lib.attrNames declared)}"
            )
          else if unknownOverrides != [ ] then
            throw (
              "preset '${name}': `overrides` names ${lib.concatStringsSep ", " unknownOverrides}, "
              + "which it does not have. Members: ${lib.concatStringsSep ", " (lib.attrNames declared)}"
            )
          else if unmet != [ ] then
            throw (
              "preset '${name}': says it provides ${lib.concatStringsSep ", " unmet}, "
              + "which no member does. Members provide: "
              + "${lib.concatStringsSep ", " actual}. Either a member was omitted "
              + "or an override does not provide what it replaced."
            )
          else
            {
              __floePreset = true;
              inherit def supplied;
              members = kept;
              overridden = lib.attrNames inputs.overrides;
            };
      };
    in
    def // { __functor = _: def.instantiate; };
}
