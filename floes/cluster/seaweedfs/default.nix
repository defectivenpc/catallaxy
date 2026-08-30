# SeaweedFS: an S3-compatible object store for a lab that has no cloud one.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "seaweedfs";

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

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.store = sigs.OBJECT_STORE;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        image = "chrislusf/seaweedfs:${inputs.version}";
      in
      {
        config.floe.provides.store = {
          readyToken = "seaweedfs/s3/ready";
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
          backs.store = [ "seaweedfs" ];
          imagesComplete = true;

          network = {
            declared = true;
            serves.s3.port = 8333;
            serves.filer.port = 8888;
            serves.master.port = 9333;
          };

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

            ready = {
              kind = "condition";
              resource = "deployment/seaweedfs-s3";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "10m";
            };
          };
        };
      }
    )
  ];
}
