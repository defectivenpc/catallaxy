# The floe registry: floes as config, not as imports.
#
# `lib/services/lib.nix`'s `configure` is the model — a framework hands out a
# submodule type, and the containing system declares an option of that type
# and folds the results into its own. The two differences from what catallaxy
# does today are the whole spike:
#
#   1. The set of floes is an *option value* (`floeModules`), not an import
#      list. So it needs no `specialArgs`, and a lab can override one floe
#      with ordinary `mkForce` instead of rebuilding the set at the `mkLab`
#      call. `nixos/modules/image/images.nix:76` is the same pattern:
#      `image.modules = mkOption { type = attrsOf deferredModule; }` with the
#      built-ins supplied as a `config` default.
#
#   2. Each floe is evaluated in its own fixpoint, so `peers` can be a module
#      argument carrying *only* other floes' `exports`. That is the boundary
#      `lib/floe-checks/boundary.nix` currently approximates with a regex over
#      source text — and the API its own error message has been recommending
#      since `mkFloe` was removed, without it existing.
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
  # floeModules.impostor` (class: "nixos") cannot be imported...". And
  # stamping `_class` onto a wrapper does not make a floe author's bare module
  # conform, because a module with `_class == null` is admissible anyway
  # (`lib/modules.nix:452`) and a wrapper does not mask a wrong `_class` on
  # what it imports.
  #
  # flake-parts needs it because it publishes across flake boundaries where
  # the consumer's submodule flavour is unknown. If this set is ever published
  # as `flake.modules.catallaxyFloe.<name>`, revisit.

  mkFloeSubmodule =
    {
      extraModules ? [ ],
    }:
    types.submoduleWith {
      class = "catallaxyFloe";

      # `importApply` rather than `specialArgs`. Its own docstring in
      # `lib/modules.nix:2113` names specialArgs as the thing it replaces:
      # passing arguments that way "effectively creates an incomplete module,
      # and requires the user of the module to manually pass the specialArgs
      # to the configuration, which is error-prone, verbose, and unnecessary."
      #
      # There is a harder reason too. `submoduleWith` *throws* when two
      # declarations of the same option supply overlapping specialArgs
      # (`lib/types.nix:1550`), while module lists merge. A framework whose
      # extension point is specialArgs cannot be extended downstream at all.
      modules = [ (lib.modules.importApply ./interface.nix { inherit modulesPath; }) ] ++ extraModules;

      # Deliberately left at the `submoduleWith` default of `false`, which is
      # the opposite of what `types.submodule` sets. It means an attrset
      # assigned into a floe slot is read as a *module*, so a lab can write
      # `floes.harbor = { imports = [ ./my-harbor.nix ]; }`. That is the whole
      # user-facing ergonomic of modular services.
      # shorthandOnlyDefinesConfig = false;
    };
in
{
  inherit mkFloeSubmodule;

  # The module a containing system imports to get a floe registry.
  #
  # `lab` is threaded in rather than read from the enclosing config because
  # the interface needs it at option-*default* evaluation time (`images` has
  # an `apply` that folds in `lab.images.registry`).
  mkRegistryModule =
    {
      lab,

      # Facts about the cluster this floe set belongs to: the *read* channel.
      #
      # Not in the spike, and found by porting gateway. A floe reads
      # `config.cluster.<x>` in 41 places today — `cluster.name`,
      # `cluster.ref.kubeContext`, `cluster.network.serviceSubnet`,
      # `cluster.provisionerOut.publishesGatewayPorts` and four others — which
      # works only because the floe is evaluated inside the cluster's own
      # option tree. Here it is not, so the facts arrive the way `lab`'s do.
      #
      # Threaded in rather than read from the enclosing config for the same
      # reason as `lab`: gateway reads `provisionerOut.publishesGatewayPorts`
      # while computing a bundle, and a floe may read it at option-*default*
      # time, before the enclosing fixpoint has settled.
      #
      # This is a view, not the cluster: what a floe *contributes* is declared
      # on the floe (`ingress`, `prerequisites`, `bundles`) and folded upward.
      # Nothing here is writable, which is the half of `cluster.<x>` that
      # currently has no boundary at all.
      cluster ? { },

      # Framework values every floe receives: `pkgs`, `cataCharts`,
      # `k8sSpecs`, `k8sHelpers`, `contracts`. Delivered through
      # `_module.args` rather than the submodule type's `specialArgs`, for two
      # reasons. They are ordinary values that exist inside the fixpoint, so
      # they do not need to be special; and `submoduleWith` throws when two
      # declarations supply overlapping `specialArgs` (`lib/types.nix:1550`),
      # which would make this the one part of the framework nobody downstream
      # could extend.
      #
      # A submodule does not inherit its parent's `_module.args` — the cluster
      # submodule in `modules/lab/types.nix:33-46` re-sets the same five by
      # hand for exactly this reason.
      args ? { },

      extraModules ? [ ],
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
          inherit extraModules;
        });
        default = { };
        # The registry is large and every instance carries the full interface.
        # `system.services` sets this for the same reason: without it, option
        # documentation renders the whole tree once per floe.
        visible = "shallow";
        description = ''
          The floes this cluster has, one instance of the floe interface each.
        '';
      };

      config.floes = lib.mapAttrs (_name: module: {
        imports = [ module ];

        _module.args = args // {
          inherit lab cluster;

          # The sanctioned cross-floe channel. A floe sees siblings' `exports`
          # and nothing else, so reading another floe's internals is no longer
          # a thing a floe *can* do rather than a thing a check catches after
          # the fact.
          #
          # The key set comes from `floeModules`, not from `config.floes`, or
          # the attribute names would be defined in terms of themselves. The
          # values stay lazy, so naming one peer does not evaluate the rest.
          peers = lib.mapAttrs (_: floe: floe.exports) config.floes;
        };
      }) config.floeModules;
    };
}
