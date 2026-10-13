# SeaweedFS: an S3-compatible object store for a lab that has no cloud one.
{
  lib,
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "seaweedfs";
  summary = "SeaweedFS, an S3-compatible object store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.seaweedfs.chart}";
      defaultText = lib.literalExpression "cataCharts.seaweedfs.chart";
      description = "Store path of the SeaweedFS Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "seaweedfs";
      description = "Namespace it runs in.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "3.80";
      description = "SeaweedFS image tag. The chart's own default lags the one this pins.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.objectStore = sigs.OBJECT_STORE;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        image = "chrislusf/seaweedfs:${inputs.version}";
      in
      {
        config.floe.provides.objectStore = {
          inherit (inputs) namespace;
          s3Endpoint = "http://seaweedfs-s3.${inputs.namespace}.svc.cluster.local:8333";

          credentials = null;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.objectStore = [ "seaweedfs" ];
          imagesComplete = true;

          bundles.seaweedfs = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            resources.db-init-config = {
              apiVersion = "v1";
              kind = "ConfigMap";
              metadata = {
                name = "seaweedfs-db-init-config";
                inherit (inputs) namespace;
              };
              data = { };
            };

            helmCharts.seaweedfs = kinds.mkHelmChart {
              replacedHooks = {
                secret-seaweedfs-db =
                  "nothing needs it: the filer here uses leveldb, the chart reads "
                  + "`WEED_MYSQL_*` with `optional: true`, and the hook's Secret carries "
                  + "the chart's hardcoded `HardCodedPassword` \u2014 not installing it is better "
                  + "than installing it";
                seaweedfs-volume-resize-hook =
                  "RBAC for a resize Job this lab does not enable; there are no volumes "
                  + "to grow on a first install";
              };
              inherit (inputs) chart namespace;
              releaseName = "seaweedfs";
              values = {
                master = {
                  replicas = 1;
                  imageOverride = image;
                };
                volume = {
                  replicas = 1;
                  imageOverride = image;
                };
                filer = {
                  replicas = 1;
                  imageOverride = image;
                };
                s3 = {
                  enabled = true;
                  imageOverride = image;
                };
              };
            };

            images.seaweedfs = {
              registry = "docker.io";
              repository = "chrislusf/seaweedfs";
              tag = inputs.version;
              digest = null;
            };

            ready = kinds.readyDeployment {
              name = "seaweedfs-s3";
              namespace = inputs.namespace;
              timeout = "10m";
            };
          };
        };
      }
    )
  ];
}
