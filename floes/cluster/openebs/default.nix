# local-path-provisioner, as the cluster's default StorageClass.
#
# Named `openebs` because that is what the shipped set called it; what it
# actually installs is Rancher's local-path provisioner, which is the chart
# `lib/charts.nix` pins.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "openebs";
  summary = "Rancher's local-path provisioner as the cluster's default StorageClass.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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

  provides.storageClass = sigs.STORAGE_CLASS;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        # A cluster has one default StorageClass, and two floes claiming it
        # would be a race. The old tree said so with `conflicts` on a bundle;
        # here exactly-one-provider says it, and a second provider of
        # STORAGE_CLASS is a link error naming both.
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
