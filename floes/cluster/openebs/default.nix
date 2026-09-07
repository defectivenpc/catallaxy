# local-path-provisioner, as the cluster's default StorageClass.
#
# Named `openebs` because that is what the shipped set called it; what it
# actually installs is Rancher's local-path provisioner, which is the chart
# `lib/charts.nix` pins.
{
  lib,
  floe,
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
  provides.storage = sigs.STORAGE_CLASS;
  out.component = kinds.component;

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
        config.floe.provides.storage = {
          inherit (inputs) className;
          isDefault = true;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.storage = [ "openebs" ];
          imagesComplete = true;
          network.declared = true;

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

            images.localPathProvisioner = {
              registry = "docker.io";
              repository = "rancher/local-path-provisioner";
              tag = "v0.0.28";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/openebs-localpv-provisioner";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "5m";
            };
          };
        };
      }
    )
  ];
}
