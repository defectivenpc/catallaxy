# The cluster extension: what a floe additionally is when it lives in a
# cluster.
#
# Everything here knows what Kubernetes is, which is exactly why none of it is
# in `./interface.nix`. Handed to `extensions` and merged into every instance
# of a cluster-scope registry, the way `lib/services/lib.nix`'s `configure`
# takes `extraRootModules` for the systemd half of a service.
#
# The base plus this is, channel for channel, the old
# `modules/lab/cluster/floe-options.nix`.
{ modulesPath }:

{
  name,
  config,
  lib,
  lab ? { },
  ...
}:

let
  inherit (lib) mkOption types;

  imageTypes = import (modulesPath + "/lab/image-types.nix") { inherit lib; };
  k8sLib = import (modulesPath + "/lab/cluster/lib/kubernetes/types.nix") { inherit lib; };
  inherit (import (modulesPath + "/lab/cluster/lib/kubernetes/drift.nix") { inherit lib; })
    driftEntryType
    ;
  inherit (import (modulesPath + "/lab/planner/types.nix") { inherit lib; }) clusterStepType;
  inherit (import (modulesPath + "/lab/cluster/secrets-generate-types.nix") { inherit lib; })
    generateType
    ;
  inherit (import (modulesPath + "/lab/cluster/prerequisite-types.nix") { inherit lib; })
    prerequisiteType
    ;

  labImages = lab.images or { };
in
{
  _class = "catallaxyFloe";

  options = {
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

    steps = mkOption {
      type = types.attrsOf clusterStepType;
      default = { };
      description = ''
        Plan steps this floe contributes, lifted into the cluster's `steps`
        under the key it was given here. A step's `origin` is filled in from
        the fold key, so an anchor or cycle error names the floe.

        Declared here rather than in the base because a cluster step carries a
        `scope` and a lab step does not — the one channel the two scopes share
        by name but not by type.
      '';
    };

    namespace = mkOption {
      type = types.str;
      default = name;
      description = "Kubernetes namespace the floe deploys into.";
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

    drift.expected = mkOption {
      type = types.listOf driftEntryType;
      default = [ ];
      description = ''
        Drift this floe expects on its own resources. Writable, so an operator
        who hits a manager name the floe author did not anticipate can append
        here without forking the floe.
      '';
    };

    # ---- contributions to the cluster --------------------------------------
    #
    # A floe writes `cluster.<x>` in the old shape, straight into the
    # containing cluster's option tree, which works only because the floe is
    # evaluated inside that tree. Here it declares the contribution on itself
    # and `./fold.nix` lifts it, exactly as `bundles` is lifted.
    #
    # Flat rather than under a `cluster.` prefix, deliberately: `cluster` is
    # the *read* channel — the framework value carrying facts about the
    # cluster this floe is in — and one name cannot be both.

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
