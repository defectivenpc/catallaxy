# Crossplane: the control plane a provider installs into.
#
# Two bundles for two readiness facts, the same split kaniop makes. The CRDs
# are established well before the controller is up: a floe applying a
# `Provider` needs the first, and one waiting for that provider to be
# reconciled needs the second.
{
  floe,
  upstream ? null,
  lib,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "crossplane";
  summary = "The Crossplane control plane, which installs providers and reconciles managed resources.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the Crossplane Helm chart. Required.";
    };

    crds = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.crds}";
      defaultText = lib.literalExpression "upstream.crds";
      description = "Store path of the chart's CRDs. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "crossplane-system";
      description = "Namespace the control plane runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.controlPlane = sigs.MANAGED_RESOURCE_CONTROL_PLANE;

  out.component = kinds.component;
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
          backs.controlPlane = [
            "crds"
            "crossplane"
          ];
          imagesComplete = true;

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.crds ];
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
