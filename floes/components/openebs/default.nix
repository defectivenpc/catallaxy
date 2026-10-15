# local-path-provisioner, as the cluster's default StorageClass.
#
# Named `openebs` because that is what the shipped set called it; what it
# actually installs is Rancher's local-path provisioner, which is the chart
# `lib/charts.nix` pins.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "openebs";
  summary = "Rancher's local-path provisioner as the cluster's default StorageClass.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the local-path-provisioner Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "openebs";
      description = "Namespace the provisioner runs in.";
    };

    className = lib.mkOption {
      type = lib.types.str;
      default = "local-path";
      description = "Name of the StorageClass it creates.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.storageClass = sigs.STORAGE_CLASS;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.storageClass = {
          inherit (inputs) className;
          isDefault = true;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.storageClass = [ "openebs" ];
          imagesComplete = true;

          bundles.openebs = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.openebs = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "local-path-provisioner";
              values.storageClass = {
                name = inputs.className;
                defaultClass = true;
              };
            };

            images.localPathProvisioner = kinds.mkImage "docker.io/rancher/local-path-provisioner:v0.0.28";

            ready = kinds.readyDeployment {
              name = "openebs-localpv-provisioner";
              namespace = inputs.namespace;
            };
          };
        };
      }
    )
  ];
}
