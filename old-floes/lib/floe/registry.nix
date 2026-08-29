# The floe registry: floes as config, not as imports.
#
# `lib/services/lib.nix`'s `configure` is the model — a framework hands out a
# submodule type, and the containing system declares an option of that type and
# folds the results into its own. Three differences from what catallaxy does
# today, and they are the spike:
#
#   1. The set of floes is an *option value* (`floeModules`), not an import
#      list. So it needs no `specialArgs`, and a lab can override one floe with
#      ordinary `mkForce` instead of rebuilding the set at the `mkLab` call.
#      `nixos/modules/image/images.nix:76` is the same pattern.
#
#   2. Each floe is evaluated in its own fixpoint, so `peers` can be a module
#      argument carrying *only* other floes' `exports`. That is the boundary
#      `lib/floe-checks/boundary.nix` approximates with a regex over source
#      text.
#
#   3. Scope is an *extension*, not a second interface. `configure` here takes
#      `extensions`, exactly as upstream's takes `extraRootModules`, so a lab
#      registry and a cluster registry are the same machinery with a different
#      module merged in. `./interface.nix` is the portable half, `./cluster.nix`
#      and `./lab.nix` are the two extensions.
{
  lib,
  modulesPath,
}:

let
  inherit (lib) mkOption types;

  # No `addInfo` wrapper here, deliberately, though flake-parts has one
  # (`extras/modules.nix`) and it was the obvious thing to copy.
  #
  # It would buy nothing. `deferredModule`'s own `merge` already calls
  # `setDefaultModuleLocation "${def.file}, via option ${showOption loc}"`
  # (`lib/types.nix:1320`), so errors name the registry slot without help —
  # verified: a wrong-class module reports "The module `<file>, via option
  # floeModules.impostor` (class: "nixos") cannot be imported...". And stamping
  # `_class` onto a wrapper does not make a floe author's bare module conform,
  # because a module with `_class == null` is admissible anyway
  # (`lib/modules.nix:452`) and a wrapper does not mask a wrong `_class` on what
  # it imports.
  #
  # flake-parts needs it because it publishes across flake boundaries where the
  # consumer's submodule flavour is unknown. If this set is ever published as
  # `flake.modules.catallaxyFloe.<name>`, revisit.

  clusterExtension = lib.modules.importApply ./cluster.nix { inherit modulesPath; };
  labExtension = lib.modules.importApply ./lab.nix { inherit modulesPath; };

  mkFloeSubmodule =
    {
      args ? { },
      extensions ? [ ],
      childExtensions ? extensions,
      peers ? { },
      peerCapabilities ? { },
    }:
    types.submoduleWith {
      class = "catallaxyFloe";

      # `importApply` rather than `specialArgs`. Its own docstring in
      # `lib/modules.nix:2113` names specialArgs as the thing it replaces:
      # passing arguments that way "effectively creates an incomplete module,
      # and requires the user of the module to manually pass the specialArgs to
      # the configuration, which is error-prone, verbose, and unnecessary."
      #
      # There is a harder reason too. `submoduleWith` *throws* when two
      # declarations of the same option supply overlapping specialArgs
      # (`lib/types.nix:1550`), while module lists merge. A framework whose
      # extension point is specialArgs cannot be extended downstream at all.
      modules = [
        (lib.modules.importApply ./interface.nix {
          inherit
            modulesPath
            args
            extensions
            childExtensions
            ;
        })
        {
          _module.args = args // {
            inherit peers peerCapabilities;
          };
        }
      ]
      ++ extensions;

      # Deliberately left at the `submoduleWith` default of `false`, which is
      # the opposite of what `types.submodule` sets. It means an attrset
      # assigned into a floe slot is read as a *module*, so a lab can write
      # `floes.harbor = { imports = [ ./my-harbor.nix ]; }`. That is the whole
      # user-facing ergonomic of modular services.
      # shorthandOnlyDefinesConfig = false;
    };
in
{
  inherit mkFloeSubmodule clusterExtension labExtension;

  # The module a containing system imports to get a floe registry.
  #
  # `configure` in all but name. Scope is chosen by what is passed as
  # `extensions`: `[ clusterExtension ]` for a cluster, `[ labExtension ]` for
  # a lab, and the same registry machinery serves both.
  mkRegistryModule =
    {
      # Framework values every floe receives, at every depth: `pkgs`,
      # `cataCharts`, `k8sSpecs`, `k8sHelpers`, `contracts`, `lab`, `cluster`.
      #
      # Delivered by baking them into the submodule *type* rather than by
      # setting `_module.args` from the enclosing config. That is forced by the
      # recursion — see the long note in `./interface.nix`. It is also what
      # upstream does (`importApply ./service.nix { inherit pkgs; }`), and it
      # sidesteps `submoduleWith`'s refusal to merge overlapping `specialArgs`.
      args ? { },

      extensions ? [ ],

      # What sub-floes are extended with. A lab registry sets this to
      # `[ clusterExtension ]`, so a lab floe holds cluster floes.
      childExtensions ? extensions,
    }:
    { config, ... }:
    {
      options.floeModules = mkOption {
        type = types.attrsOf types.deferredModule;
        default = { };
        description = ''
          The floe set, as modules. This is the registry.

          An option rather than a parameter, so the bundled set arrives as a
          `config` default and a consumer can add to it, replace one entry, or
          `mkForce` the lot — the same shape as `image.modules` upstream.
        '';
      };

      options.floes = mkOption {
        type = types.attrsOf (mkFloeSubmodule {
          inherit args extensions childExtensions;

          # The sanctioned cross-floe channel. A floe sees siblings' `exports`
          # and nothing else, so reading another floe's internals is no longer
          # a thing a floe *can* do rather than a thing a check catches after
          # the fact.
          #
          # Lazy: `mapAttrs` does not force its values, so naming one peer does
          # not evaluate the rest.
          peers = lib.mapAttrs (_: floe: floe.exports) config.floes;

          # The same channel for the typed half: what each sibling claims to
          # do, so `dependencies` can be resolved by job rather than by name.
          peerCapabilities = lib.mapAttrs (_: floe: floe.capabilities.provides) config.floes;
        });
        default = { };

        # The registry is large and every instance carries the full interface.
        # `system.services` sets this for the same reason: without it, option
        # documentation renders the whole tree once per floe.
        visible = "shallow";

        description = ''
          The floes at this scope, one instance of the floe interface each.
        '';
      };

      config.floes = lib.mapAttrs (_name: module: { imports = [ module ]; }) config.floeModules;
    };
}
