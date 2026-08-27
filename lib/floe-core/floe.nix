# mkFloe: a unit with declared surfaces (inputs, requires, requiresMany,
# provides, out) and a body of ordinary NixOS-style modules.
#
# Surfaces by writer:
#   floe.inputs    written by the deployer (instantiate), read-only to the body
#   floe.requires  written by the linker, read-only to the body
#   floe.provides  written by the body, sealed against signatures at link
#   floe.out.<k>   written by the body, checked against kind schemas at link
#
# Input types are native NixOS option declarations (lib.mkOption / lib.types).
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
      inputs ? { },
      requires ? { },
      requiresMany ? { },
      provides ? { },
      out ? { },
      modules ? [ ],
    }:
    let
      hasInputs = inputs != { };

      # Eager instantiation pre-check: a mini evalModules containing only the
      # input declarations and the supplied definitions, deep-forced. Errors
      # are the module system's own (missing required input, unknown input,
      # type mismatch), wrapped in the floe's name. No body modules run here.
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

      def = {
        __floeDef = true;
        inherit
          name
          inputs
          requires
          requiresMany
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
      };
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
