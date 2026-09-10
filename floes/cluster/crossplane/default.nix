# Crossplane: the control plane a provider installs into.
#
# Two bundles for two readiness facts, the same split kaniop makes. The CRDs
# are established well before the controller is up: a floe applying a
# `Provider` needs the first, and one waiting for that provider to be
# reconciled needs the second.
{
  catallaxy,
  lib,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "crossplane";
  summary = "The Crossplane control plane, which installs providers and reconciles managed resources.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the Crossplane Helm chart. Required.";
    };

    crds = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the chart's CRDs. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "crossplane-system";
      description = "Namespace the control plane runs in.";
    };
  };

  provides.controlPlane = sigs.MANAGED_RESOURCE_CONTROL_PLANE;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.controlPlane = {
          inherit (inputs) namespace;
          providerKind = "pkg.crossplane.io/Provider";
        };

        config.floe.out.component = kinds.mkComponent {
          # Both, in order: applying a `Provider` needs the kind to exist and
          # something reconciling it.
          backs.controlPlane = [
            "crds"
            "crossplane"
          ];
          imagesComplete = true;

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.crds ];
            # All sixteen, read off the pinned set rather than recalled:
            # `Function` is in `pkg.` and not `apiextensions.`, which is the
            # kind of thing a from-memory list gets wrong.
            crds = [
              "apiextensions.crossplane.io/CompositeResourceDefinition"
              "apiextensions.crossplane.io/Composition"
              "apiextensions.crossplane.io/CompositionRevision"
              "apiextensions.crossplane.io/EnvironmentConfig"
              "apiextensions.crossplane.io/Usage"
              "pkg.crossplane.io/Configuration"
              "pkg.crossplane.io/ConfigurationRevision"
              "pkg.crossplane.io/ControllerConfig"
              "pkg.crossplane.io/DeploymentRuntimeConfig"
              "pkg.crossplane.io/Function"
              "pkg.crossplane.io/FunctionRevision"
              "pkg.crossplane.io/ImageConfig"
              "pkg.crossplane.io/Lock"
              "pkg.crossplane.io/Provider"
              "pkg.crossplane.io/ProviderRevision"
              "secrets.crossplane.io/StoreConfig"
            ];
          };

          bundles.crossplane = kinds.mkBundle {
            needs = [ "crds" ];
            createNamespaces = [ inputs.namespace ];

            images.crossplane = kinds.mkImage "xpkg.upbound.io/crossplane/crossplane:v1.18.2";

            helmCharts.crossplane = kinds.mkHelmChart {
              chart = inputs.chart;
              releaseName = "crossplane";
              namespace = inputs.namespace;
              # The chart ships no CRDs at all — not in `crds/`, not in
              # templates — which is why `lib/charts.nix` pins them from the
              # tag separately and `bundles.crds` is their only source.
              values = { };
            };

            ready = kinds.readyDeployment {
              name = "crossplane";
              namespace = inputs.namespace;
              timeout = "5m";
            };
          };
        };
      }
    )
  ];
}
