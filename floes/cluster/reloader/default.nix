# Stakater Reloader: rolls a workload when a Secret or ConfigMap it names
# changes.
#
# The old floe also exported `mkPatches`, a function that built kustomize
# patch entries for a caller's chart. A signature cannot carry a function —
# RFC 0001 rules them out because they cannot be checked at eval, do not
# serialize, and defeat `checkFloe` — and it was the only such export in the
# catalogue. The two annotation keys travel on the signature instead, and
# `lib/k8s-annotations.nix` builds the annotation from them.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "reloader";
  summary = "Reloader, which restarts a workload when a Secret or ConfigMap it mounts changes.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the Reloader Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "reloader";
      description = "Namespace the controller runs in.";
    };
  };

  provides.reload = sigs.CONFIG_RELOAD;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.reload = {
          secretAnnotation = "secret.reloader.stakater.com/reload";
          configMapAnnotation = "configmap.reloader.stakater.com/reload";
        };

        config.floe.out.component = kinds.mkComponent {
          backs.reload = [ "reloader" ];
          imagesComplete = true;

          bundles.reloader = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.reloader = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "reloader";
              values.reloader = {
                watchGlobally = true;
                reloadOnCreate = true;
              };
            };

            images.controller = {
              registry = "ghcr.io";
              repository = "stakater/reloader";
              tag = "v1.4.19";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/reloader-reloader";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
