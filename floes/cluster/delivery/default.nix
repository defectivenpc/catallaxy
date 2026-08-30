# How this cluster's manifests get applied.
#
# The one floe in the catalogue that installs nothing. It exists so a floe
# that renders differently under GitOps than under a direct apply can ask,
# rather than reading a lab option and coupling itself to the lab's shape.
#
# It emits no bundles at all, which is why it requires no cluster: there is
# nothing for it to install into.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "delivery";

  inputs = {
    strategy = lib.mkOption {
      type = lib.types.enum [
        "kapp"
        "argocd"
        "fleet"
      ];
      default = "kapp";
      description = ''
        Whether the cluster is reconciled by a direct apply or by a CD tool
        reading a git remote.
      '';
    };

    bootstrapTool = lib.mkOption {
      type = lib.types.enum [
        "kubectl-ssa"
        "helm"
        "none"
      ];
      default = "kubectl-ssa";
      description = ''
        Which imperative tool applies the install-target set. Ignored when
        `strategy = "kapp"`, because then everything is the install target.
      '';
    };
  };

  provides.policy = sigs.DELIVERY_POLICY;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.policy = {
          inherit (inputs) strategy bootstrapTool;
          appliedByKapp = inputs.strategy == "kapp";
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;
          network.declared = true;
        };
      }
    )
  ];
}
