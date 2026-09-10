# SeaweedFS: an S3-compatible object store for a lab that has no cloud one.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "seaweedfs";
  summary = "SeaweedFS, an S3-compatible object store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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

  provides.objectStore = sigs.OBJECT_STORE;

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

          # The chart's S3 gateway runs without authentication here, so there
          # is no credential to hand out and saying so is the truthful answer.
          # `null` rather than an omitted field: a consumer has to handle the
          # unauthenticated case explicitly rather than reading an attribute
          # that is not there.
          #
          # Turning auth on means an `existingConfigSecret` holding a
          # seaweedfs identities file, which is a different shape from an
          # access-key pair — so it wants its own input and a generated
          # credential, not a default flipped here.
          credentials = null;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.objectStore = [ "seaweedfs" ];
          imagesComplete = true;

          bundles.seaweedfs = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            # The chart's filer StatefulSet mounts this ConfigMap
            # unconditionally (`templates/filer-statefulset.yaml:317-319`) and
            # no template in the chart creates it. The volume carries no
            # `optional: true`, so the kubelet blocks and the filer pod never
            # starts — an upstream bug in seaweedfs 4.0.0.
            #
            # It holds SQL schema for a filer backed by a database. This one
            # uses the default leveldb store and never reads it, so an empty
            # ConfigMap is the whole fix. `cata lab lint`'s reference rule is
            # what found this; nothing else would have until someone stood
            # seaweedfs up and watched a pod sit in ContainerCreating.
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
