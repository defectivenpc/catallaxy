# mkFloe: a unit with declared surfaces (inputs, requires, requiresOptional,
# provides, out) and a body of ordinary NixOS-style modules.
{ lib, types }:

rec {
  # Deferred-value token constructor, exposed to bodies as `floe.mkDeferred`
  # via specialArgs (bound to the unit's link name).
  mkDeferredFor = unitName: path: {
    __deferred = true;
    source = unitName;
    inherit path;
    phase = "post-apply";
  };

  mkFloe =
    {
      name,

      summary ? null,

      inputs ? { },
      requires ? { },

      requiresOptional ? { },
      provides ? { },
      out ? { },
      modules ? [ ],
    }:
    let
      _ =
        if summary == null then
          throw (
            "floe '${name}': needs a one-line `summary` saying what it installs. "
            + "Nix cannot read comments, so the header prose above reaches no tool; "
            + "this is the line the generated interface document titles it with."
          )
        else
          null;

      hasInputs = inputs != { };

      # An input is what a deployer writes, so it takes a NixOS option type.
      # Handed a floe data schema the module system fails inside nixpkgs with
      # `attribute 'deprecationMessage' missing`, which names neither the floe
      # nor the input.
      floeTypedInputs = lib.attrNames (
        lib.filterAttrs (_: opt: lib.isAttrs opt && ((opt.type or null) ? tag)) inputs
      );

      _inputTypes =
        if floeTypedInputs == [ ] then
          null
        else
          throw (
            "floe '${name}': input(s) ${lib.concatStringsSep ", " floeTypedInputs} are "
            + "declared with `T`, the floe data schema. An input is what a deployer "
            + "writes, so it takes a NixOS option type — `lib.types.str`, not `T.str`. "
            + "`T` is for values that cross a floe boundary."
          );

      checkInputs =
        supplied:
        if !hasInputs then
          (
            if supplied == { } then
              supplied
            else
              throw (
                "floe '${name}': takes no inputs, but got: " + lib.concatStringsSep ", " (lib.attrNames supplied)
              )
          )
        else
          let
            ev = lib.evalModules {
              modules = [
                { options.floe.inputs = inputs; }
                { config.floe.inputs = supplied; }
              ];
            };
          in
          builtins.addErrorContext "while instantiating floe '${name}'" (
            builtins.deepSeq ev.config.floe.inputs ev.config.floe.inputs
          );

      def = builtins.seq _ (
        builtins.seq _inputTypes {
          __floeDef = true;
          inherit
            name
            summary
            inputs
            requires
            requiresOptional
            provides
            out
            modules
            ;

          # instantiate :: attrset -> instance
          # inputsChecked carries the validated, defaults-filled inputs.
          instantiate = supplied: {
            __floeInstance = true;
            inherit def;
            inputsChecked = checkInputs supplied;
          };
        }
      );
    in
    def;

  # evalFloe: run one floe's isolated evalModules with resolved requires
  # injected. Used by the linker; not part of the author-facing API.
  evalFloe =
    {
      instance,
      unitName,
      resolvedRequires,
    }:
    let
      def = instance.def;
      t = lib.types;
      base = {
        options.floe = {
          name = lib.mkOption {
            type = t.str;
            default = unitName;
          };
          inputs = lib.mkOption {
            type = t.raw;
            default = instance.inputsChecked;
          };
          requires = lib.mkOption {
            type = t.raw;
            default = resolvedRequires;
          };
          provides = lib.mkOption {
            type = t.attrsOf t.raw;
            default = { };
          };
          out = lib.mapAttrs (
            _kName: _kind:
            lib.mkOption {
              type = t.attrsOf t.raw;
              default = { };
            }
          ) def.out;
        };
      };
    in
    lib.evalModules {
      specialArgs.floe = {
        mkDeferred = mkDeferredFor unitName;
      };
      modules = def.modules ++ [ base ];
    };
}
