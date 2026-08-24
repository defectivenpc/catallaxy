# The floe interface: the one declaration of what a floe is.
#
# This is the typeclass. `modules/lab/cluster/floe-options.nix` is the shape
# it replaces, and the difference is the whole point of the exercise: that one
# is a *function returning a module that declares `options.floes.<name>`*, so
# the interface is declared once per floe, at a path computed from the floe's
# own name. There is no floe type there — `config.floes` is not an option
# anywhere in the tree, it is just the union of 29 modules that each happened
# to declare one attribute of it.
#
# Here the interface is declared once and each floe *instantiates* it, which
# is what `types.submoduleWith { class; modules = [ this ]; }` means. Three
# things fall out that could not be had before:
#
#   - a floe's `config` is its own, so it writes `bundles.x` rather than
#     `floes.reloader.bundles.x`;
#   - the set of floes is a config value rather than an import list, so it
#     needs no `specialArgs` and a lab can override one;
#   - `peers` can be a module argument carrying only other floes' `exports`,
#     which makes rule 1 structural instead of a regex over source text.
#
# The pattern is nixpkgs 25.11's Modular Services
# (`nixos/doc/manual/development/modular-services.md`), whose opening line is
# this project's problem statement almost verbatim: "Traditionally, NixOS
# services were defined using sets of options *in* modules, not *as* modules.
# This made them non-modular." See `lib/services/lib.nix` for the reference
# implementation of a framework constructor, and `nixos/modules/image/images.nix`
# for the `attrsOf deferredModule` registry.
{ modulesPath }:

{
  name,
  config,
  lib,
  lab,
  ...
}:

let
  inherit (lib) mkOption mkEnableOption types;

  imageTypes = import (modulesPath + "/lab/image-types.nix") { inherit lib; };
  k8sLib = import (modulesPath + "/lab/cluster/lib/kubernetes/types.nix") { inherit lib; };
  inherit (import (modulesPath + "/lab/cluster/lib/kubernetes/drift.nix") { inherit lib; })
    driftEntryType
    ;
  inherit (import (modulesPath + "/lab/planner/types.nix") { inherit lib; }) clusterStepType;
  infraTypes = import ../infra/types.nix { inherit lib; };
  inherit (import (modulesPath + "/lab/cluster/secrets-generate-types.nix") { inherit lib; })
    generateType
    ;
  inherit (import (modulesPath + "/lab/cluster/prerequisite-types.nix") { inherit lib; })
    prerequisiteType
    ;

  opsTypes = import (modulesPath + "/lab/ops/types.nix") { inherit lib; };
  opsCommandType = opsTypes.opsCommandType { inherit (opsTypes) optionType argType; };

  # Copied rather than imported from `modules/lab/default.nix:6`, which does not
  # export it. Same two fields; if that one grows a third this one is wrong.
  assertionType = types.submodule {
    options = {
      assertion = mkOption {
        type = types.bool;
        description = "True = check passes. False = violation reported.";
      };
      message = mkOption {
        type = types.str;
        description = ''
          Diagnostic shown when the assertion fails. Mention the offending
          option path and what the user should change.
        '';
      };
    };
  };

  labImages = lab.images or { };
in
{
  # A nominal type. Assigning a plain NixOS module into a floe slot now fails
  # with "cannot be imported into a module evaluation that expects class
  # catallaxyFloe" rather than with a pile of "option does not exist" errors
  # from deep inside the merge. `lib/modules.nix:452` is the check.
  _class = "catallaxyFloe";

  options = {
    enable = mkEnableOption "this floe";

    exports = mkOption {
      # An empty submodule, which each floe *extends* by declaring
      # `options.exports.<field>` with its own type and default. Option types
      # merge — two `mkOption`s with `types.submodule` types union their module
      # lists — so the interface guarantees the attribute exists while the floe
      # still owns what is in it.
      #
      # Not `lazyAttrsOf raw`, which was the first thing tried. Freeform
      # exports cannot carry per-field types or defaults, and the defaults are
      # load-bearing: `every-floe-export-has-a-default` reads every floe's
      # exports with *nothing enabled*, because a consumer may read an export
      # while computing its own option default.
      #
      # Declared here at all is the change from `floe-options.nix`, which does
      # not mention exports —`docs/book/src/reference/floe-api.md:61` says
      # "`exports` is not special, it is a nested option like any other", and
      # that is precisely why nothing could enforce the boundary.
      type = types.submodule { };
      default = { };
      description = ''
        This floe's public interface: what a sibling floe may read.

        The only channel a peer sees. Everything else on this submodule is
        private, and after the move to `peers` that is structural rather than
        a convention a regex checks.
      '';
    };

    bundles = mkOption {
      type = types.attrsOf (k8sLib.bundleTypeOwnedBy name);
      default = { };
      description = ''
        Installable bundles this floe declares, lifted into the cluster's
        `bundles` with the key it was given here.

        Ownership is the path it was written at rather than a stamp applied
        afterwards, so nothing has to walk the module system's own `mkIf` and
        `mkMerge` nodes to work out which floe owns one.
      '';
    };

    infra.resources = mkOption {
      type = types.attrsOf infraTypes.resourceType;
      default = { };
      description = ''
        Infrastructure this floe needs provisioned, lifted into the lab's
        stacks under the key it was given here.

        The other camp from `bundles`. A bundle is a Kubernetes resource a
        controller reconciles forever; this is a resource a plan/apply tool
        creates once and records in state.
      '';
    };

    steps = mkOption {
      type = types.attrsOf clusterStepType;
      default = { };
      description = ''
        Plan steps this floe contributes, lifted into the cluster's `steps`
        under the key it was given here. A step's `origin` is filled in from
        this path, so an anchor or cycle error names the floe.
      '';
    };

    ops = mkOption {
      type = types.attrsOf (types.attrsOf opsCommandType);
      default = { };
      description = ''
        Operational commands this floe publishes, keyed by category then by
        name to match the `<lab>-ops <category> <name>` invocation.
      '';
    };

    secrets.generate = mkOption {
      type = types.attrsOf generateType;
      default = { };
      description = ''
        Secrets this floe mints for itself, with no value authored anywhere.

        A value that exists before the lab does belongs in
        `lab.secrets.managed`, and one another cluster mints belongs in
        `secrets.subscribe`. Neither is the floe's to declare.
      '';
    };

    verify = mkOption {
      type = types.attrsOf (import (modulesPath + "/lab/verify-types.nix") { inherit lib; }).checkType;
      default = { };
      description = ''
        Assertions this floe makes about itself once it is running, collected
        into the lab's `cata lab verify` run. The live counterpart to lint.
      '';
    };

    lint = mkOption {
      type = types.attrsOf (import (modulesPath + "/lab/lint-types.nix") { inherit lib; }).checkType;
      default = { };
      description = ''
        Checks this floe makes about its own rendered manifests. The static
        counterpart to `verify`: lint reads what was rendered and needs no
        cluster.
      '';
    };

    images = mkOption {
      type = types.attrsOf imageTypes.imageType;
      default = { };
      apply = imageTypes.retarget {
        registry = labImages.registry or null;
        pinned = labImages.pinned.${name} or { };
      };
      description = ''
        Every image this floe needs, including the ones its chart pulls,
        keyed by a label that is part of the floe's interface.

        What is read back is what the lab settled on, not only what the floe
        wrote: `lab.images.registry` and `lab.images.pinned.<name>` are folded
        in here, so a floe gets retargeting without knowing it exists.
      '';
    };

    imagesComplete = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether `images` names every image this floe renders, chart ones
        included. Off by default so a floe part-way through declaring is not a
        build failure.
      '';
    };

    network = mkOption {
      type = (import (modulesPath + "/lab/network-policy-types.nix") { inherit lib; }).networkType;
      default = { };
      description = ''
        Traffic this floe needs, as intent rather than as policy, used when a
        cluster turns `security.networkPolicies` on.

        Both halves of a cross-floe flow are declared, one by each floe,
        because a default-deny namespace refuses in both directions.
      '';
    };

    namespace = mkOption {
      type = types.str;
      default = name;
      description = "Kubernetes namespace the floe deploys into.";
    };

    version = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Version of the packaged software (informational).

        Set by the floe in its own `config` now, rather than passed as an
        argument to a `floeOptions` call that no longer exists.
      '';
    };

    drift.expected = mkOption {
      type = types.listOf driftEntryType;
      default = [ ];
      description = ''
        Drift this floe expects on its own resources. Writable, so an operator
        who hits a manager name the floe author did not anticipate can append
        here without forking the floe.
      '';
    };

    capabilities = mkOption {
      type = (import ../contracts/capability.nix { inherit lib; }).capabilitiesType;
      default = { };
      description = ''
        What job this floe does, so the cluster can recognise another floe
        doing the same one.

        What a floe *needs* is said by its bundles, as a name in the one
        dependency namespace, and never as the name of another floe.
      '';
    };

    assertions = mkOption {
      type = types.listOf assertionType;
      default = [ ];
      description = ''
        Hard config-validity checks this floe makes about its own
        configuration, folded into the cluster's `assertions`.

        Written at the floe's own path now rather than at the cluster's,
        which is what says whose constraint it is. Eleven floes write
        cluster-scope `assertions` today, and nothing in the failure names
        which one of them objected.
      '';
    };

    warnings = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Non-fatal complaints, folded into the cluster's `warnings`.";
    };

    # --- contributions to the cluster ----------------------------------------
    #
    # A floe writes `cluster.<x>` today, straight into the containing cluster's
    # own option tree, which works only because the floe is evaluated inside
    # that tree. Here it declares the contribution on itself and the cluster
    # folds it, exactly as it already folds `bundles` (`bundles.nix:44`).
    #
    # Flat rather than under a `cluster.` prefix, deliberately: `cluster` is the
    # *read* channel — the module argument carrying facts about the cluster this
    # floe is in — and one name cannot be both. `bundles`, `steps` and `ops` are
    # already cluster contributions declared flat, so this follows them.
    #
    # Two of the eight are here, the two `gateway` needs. The other six
    # (`registryDomains`, `bootstrapManifests`, `provisions`,
    # `kubernetes.uncheckedResources`, `trust.caConfigMaps`,
    # `secrets.projections`) are declared as their floes are ported, so nothing
    # here is a channel no instance has ever driven.

    ingress = mkOption {
      type = types.attrsOf types.port;
      default = { };
      description = ''
        Ports the lab's proxy should dial this cluster's ingress on, merged
        into `cluster.ingress`.

        Keys are `cluster.ingress`'s own (`httpPort`, `httpsPort`,
        `passthroughPort`), and an unknown one fails there rather than here —
        `attrsOf port` cannot name three options and still let a floe answer
        only the one it knows. Two floes answering the same key is a
        conflicting definition, which is right: nothing merges two ports.
      '';
    };

    prerequisites = mkOption {
      type = types.attrsOf prerequisiteType;
      default = { };
      description = ''
        Things several floes need installed and exactly one installation of
        which is correct, merged into `cluster.prerequisites`.

        Not a bundle, because a bundle is stamped with the floe that declared
        it and two floes declaring the same one is then a conflict rather than
        a merge — enabling cilium and gateway together failed outright, and
        both were right to install the Gateway API CRDs.
      '';
    };

    overrides = mkOption {
      type = types.submodule {
        options = {
          extraAnnotations = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Extra annotations merged onto every resource this floe emits.";
          };
          extraLabels = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Extra labels merged onto every resource this floe emits.";
          };
          serviceType = mkOption {
            type = types.enum [
              "ClusterIP"
              "NodePort"
              "LoadBalancer"
            ];
            default = "ClusterIP";
            description = "Default Service type for any Service this floe emits.";
          };
          nodeSelector = mkOption {
            type = types.attrsOf types.str;
            default = { };
            description = "Extra nodeSelector merged onto workload pod templates.";
          };
          tolerations = mkOption {
            type = types.listOf types.attrs;
            default = [ ];
            description = "Extra tolerations appended to workload pod templates.";
          };
        };
      };
      default = { };
      description = ''
        Standard escape hatch for provider-specific customizations, so
        provider assumptions do not leak into the floe's module body.
      '';
    };
  };
}
