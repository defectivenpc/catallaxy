# mkFloe: a unit with declared surfaces (inputs, requires, requiresOptional,
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

      # One line saying what this floe installs. Required, because Nix cannot
      # read comments: a floe's header prose reaches no tool, so without this
      # the generated interface document has no title and the only
      # machine-readable thing about a floe is its name.
      #
      # Defaulted to null and refused below rather than left out of the
      # pattern, so the pattern stays closed — an unknown key is still an
      # error — and the author gets a message saying what to write.
      summary ? null,

      inputs ? { },
      requires ? { },

      # Zero-or-one. Resolves to `null` when nothing provides the signature,
      # refuses two providers exactly as `requires` does, and orders the same
      # way — the consumer follows whatever satisfied it.
      #
      # This replaced `requiresMany`, a fan-in that collected every provider.
      # Two things were wrong with that. It carried no ordering: the elaborator
      # derived edges from exactly-one holes only, on the theory that a fan-in
      # always runs the other way — true for the gateway collecting routes,
      # false for a collector consuming its backends, which rendered three
      # waves before the Prometheus it wrote to. And the collection model
      # itself said only the floe installing a capability may render resources
      # using it, which is not how Kubernetes works: a registered CRD is a
      # primitive anyone may use. A floe now ships a constructor
      # (`kinds.mkRoute`, `kinds.mkGeneratedSecret`) and the consumer emits
      # the resource into its own bundle.
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

      def = builtins.seq _ {
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
