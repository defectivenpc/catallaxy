{
  modulesPath,
  args ? { },
  extensions ? [ ],

  # What this floe's *sub*-floes are extended with, which is not always what
  # this floe is extended with — and that asymmetry is the point of the lab
  # scope. A lab floe holds cluster floes: it carries `./lab.nix` while its
  # children carry `./cluster.nix`.
  #
  # Upstream draws the same line and is explicit about it — `extraRootModules`
  # are "loaded into the 'root' service submodule, but not into its
  # sub-`services`. That's the modules' own responsibility." The difference
  # here is only that catallaxy's scope hierarchy is real and finite (lab
  # contains clusters), so the framework can say what the next scope down is
  # instead of leaving it to each module.
  #
  # Defaults to `extensions`, which is right within a scope: a sub-floe of a
  # cluster floe is another cluster floe.
  childExtensions ? extensions,
}:

{
  name,
  config,
  lib,
  peerCapabilities ? { },
  ...
}:

let
  inherit (lib) mkOption mkEnableOption types;

  wiring = import ./wiring.nix { inherit lib; };

  opsTypes = import (modulesPath + "/lab/ops/types.nix") { inherit lib; };
  opsCommandType = opsTypes.opsCommandType { inherit (opsTypes) optionType argType; };

  infraTypes = import ../infra/types.nix { inherit lib; };

  # Copied rather than imported from `modules/lab/default.nix:6`, which does
  # not export it. Same two fields; if that one grows a third this one is
  # wrong.
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

  # The recursion. Self-imported by path, the way `lib/services/service.nix`
  # does it, so a sub-floe is the same type as its parent all the way down.
  #
  # `peers` is a parameter rather than something the sub-floe computes,
  # because a floe's peers are its *siblings* — which only its parent knows.
  floeSubmodule =
    { peers, peerCapabilities }:
    types.submoduleWith {
      class = "catallaxyFloe";
      modules = [
        (lib.modules.importApply ./interface.nix {
          inherit modulesPath args childExtensions;
          extensions = childExtensions;
        })
        {
          _module.args = args // {
            inherit peers peerCapabilities;
          };
        }
      ]
      ++ childExtensions;
    };
in
{
  # A nominal type. Assigning a plain NixOS module into a floe slot fails with
  # "cannot be imported into a module evaluation that expects class
  # catallaxyFloe" rather than with a pile of "option does not exist" errors
  # from deep inside the merge. `lib/modules.nix:452` is the check.
  _class = "catallaxyFloe";

  options = {
    enable = mkEnableOption "this floe";

    # ---- composition -------------------------------------------------------

    floes = mkOption {
      type = types.attrsOf (floeSubmodule {
        peers = lib.mapAttrs (_: floe: floe.exports) config.floes;
        peerCapabilities = lib.mapAttrs (_: floe: floe.capabilities.provides) config.floes;
      });
      default = { };

      # Without this, option documentation renders the entire interface once
      # per floe, at every depth. `lib/services/service.nix:40` sets it for the
      # same reason, and it is most of the 82% duplication measured on the old
      # shape.
      visible = "shallow";

      description = ''
        Floes this floe is composed of.

        An ownership relation and nothing more: holding a sub-floe does not
        order it, deploy it, or wire it to anything, exactly as upstream's
        `services` option does not imply a systemd slice. What it does buy is
        that every channel below is collected through the whole tree, so a
        composition is itself a valid floe.

        This is what makes a lab floe a floe rather than a second interface:
        a lab floe is one whose sub-floes are cluster floes.
      '';
    };

    # ---- the public surface ------------------------------------------------

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
      type = types.submodule { };
      default = { };
      description = ''
        This floe's public interface: what a sibling floe may read.

        The only channel a peer sees. Everything else on this submodule is
        private, and after the move to `peers` that is structural rather than
        a convention a regex checks.
      '';
    };

    capabilities = mkOption {
      type = (import ../contracts/capability.nix { inherit lib; }).capabilitiesType;
      default = { };
      description = ''
        What job this floe does, so the cluster can recognise another floe
        doing the same one.

        The producing half of the typed wiring in `./wiring.nix`: a consumer
        names a capability, and what it gets back is the contract's shape
        rather than whatever the provider happened to export.
      '';
    };

    # ---- typed wiring ------------------------------------------------------

    dependencies = mkOption {
      type = types.attrsOf wiring.requirementType;
      default = { };
      example = lib.literalExpression ''{ gateway.capability = "api-gateway"; }'';
      description = ''
        Jobs this floe needs done, each under a slot name of its own choosing.

        The consuming half of `capabilities`. A floe names the job, never the
        floe that does it, so a lab can swap the provider without the consumer
        changing — and an unprovided job is a sentence naming this floe and
        that capability, rather than a missing-attribute error naming neither.
      '';
    };

    deps = mkOption {
      type = types.attrsOf types.raw;
      internal = true;
      readOnly = true;
      default = wiring.resolve {
        floeName = name;
        inherit (config) dependencies;
        inherit peerCapabilities;
      };
      defaultText = lib.literalExpression "resolved from `dependencies` against peers' `capabilities.provides`";
      description = ''
        What `dependencies` resolved to: `<slot> = <the contract payload the
        provider claimed>`.

        Typed by the *contract*, not by the provider — `claim` validates a
        provider's payload against the contract's declared fields, so what is
        read here has the same shape whichever floe is answering.
      '';
    };

    # ---- contributions -----------------------------------------------------

    ops = mkOption {
      type = types.attrsOf (types.attrsOf opsCommandType);
      default = { };
      description = ''
        Operational commands this floe publishes, keyed by category then by
        name to match the `<lab>-ops <category> <name>` invocation.
      '';
    };

    lint = mkOption {
      type = types.attrsOf (import (modulesPath + "/lab/lint-types.nix") { inherit lib; }).checkType;
      default = { };
      description = ''
        Checks this floe makes about its own rendered output. The static
        counterpart to `verify`: lint reads what was rendered and needs
        nothing running.
      '';
    };

    verify = mkOption {
      type = types.attrsOf (import (modulesPath + "/lab/verify-types.nix") { inherit lib; }).checkType;
      default = { };
      description = ''
        Assertions this floe makes about itself once it is running, collected
        into `cata lab verify`. The live counterpart to lint.
      '';
    };

    infra.resources = mkOption {
      type = types.attrsOf infraTypes.resourceType;
      default = { };
      description = ''
        Infrastructure this floe needs provisioned, lifted into the lab's
        stacks under the key it was given here.

        The other camp from a cluster floe's `bundles`. A bundle is a resource
        a controller reconciles forever; this is one a plan/apply tool creates
        once and records in state.
      '';
    };

    assertions = mkOption {
      type = types.listOf assertionType;
      default = [ ];
      description = ''
        Hard config-validity checks this floe makes about its own
        configuration.

        Written at the floe's own path rather than at the containing scope's,
        which is what says whose constraint it is. `./fold.nix` collects these
        through the whole tree and prefixes each message with the floe path,
        so a failure names the floe that objected — which the eleven floes
        writing cluster-scope assertions today cannot do.
      '';
    };

    warnings = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Non-fatal complaints, collected and path-prefixed like `assertions`.";
    };

    # ---- identity ----------------------------------------------------------

    version = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Version of the packaged software (informational).

        Set by the floe in its own `config`, rather than passed as an argument
        to a `floeOptions` call that no longer exists.
      '';
    };
  };
}
