# Loki: log ingest and query.
#
# Filesystem storage only. The old floe also had an S3 backend pointing at
# seaweedfs, which is a consumer choice made by a lab with an object store;
# it comes back when a lab asks for it.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  content,
  ...
}:

floe.mkFloe {
  name = "loki";
  summary = "Loki, the log store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the Loki Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "loki";
      description = "Namespace Loki runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.logs = sigs.LOG_INGEST;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        host = "loki.${inputs.namespace}.svc.cluster.local";
        base = "http://${host}:3100";
      in
      {
        config.floe.provides.logs = {
          pushUrl = "${base}/loki/api/v1/push";
          queryUrl = base;
          otlpUrl = "${base}/otlp";
        };

        config.floe.out.component = content.mkComponent {
          backs.logs = [ "loki" ];
          imagesComplete = true;

          bundles.loki = content.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.loki = content.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "loki";
              values = {
                deploymentMode = "SingleBinary";
                singleBinary.replicas = 1;
                loki = {
                  auth_enabled = false;
                  commonConfig.replication_factor = 1;
                  storage.type = "filesystem";
                  schemaConfig.configs = [
                    {
                      from = "2024-04-01";
                      store = "tsdb";
                      object_store = "filesystem";
                      schema = "v13";
                      index = {
                        prefix = "index_";
                        period = "24h";
                      };
                    }
                  ];
                };
                read.replicas = 0;
                write.replicas = 0;
                backend.replicas = 0;
                chunksCache.enabled = false;
                resultsCache.enabled = false;
              };
            };

            images.loki = content.mkImage "docker.io/grafana/loki:3.5.0";
            images.canary = content.mkImage "docker.io/grafana/loki-canary:3.5.0";
            images.sidecar = content.mkImage "docker.io/kiwigrid/k8s-sidecar:1.30.3";
            images.gateway = content.mkImage "docker.io/nginxinc/nginx-unprivileged:1.28-alpine";

            ready = content.readyCondition {
              resource = "statefulset/loki";
              condition = "Available";
              namespace = inputs.namespace;
              timeout = "10m";
            };
          };
        };
      }
    )
  ];
}
