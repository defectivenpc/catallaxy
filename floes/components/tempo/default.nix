# Tempo: trace ingest and query.
#
# Local storage only, for the same reason as Loki: the S3 backend is a
# consumer choice a lab with an object store makes.
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
  name = "tempo";
  summary = "Tempo, the trace store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the Tempo Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "tempo";
      description = "Namespace Tempo runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.traces = sigs.TRACE_INGEST;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        host = "tempo.${inputs.namespace}.svc.cluster.local";
      in
      {
        config.floe.provides.traces = {
          queryUrl = "http://${host}:3100";
          otlpGrpc = "${host}:4317";
          otlpHttp = "http://${host}:4318";
        };

        config.floe.out.component = content.mkComponent {
          backs.traces = [ "tempo" ];
          imagesComplete = true;

          bundles.tempo = content.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.tempo = content.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "tempo";
              values.tempo = {
                storage.trace = {
                  backend = "local";
                  local.path = "/var/tempo/traces";
                };
                receivers.otlp.protocols = {
                  grpc.endpoint = "0.0.0.0:4317";
                  http.endpoint = "0.0.0.0:4318";
                };
              };
            };

            images.tempo = content.mkImage "docker.io/grafana/tempo:2.7.1";

            ready = content.readyCondition {
              resource = "statefulset/tempo";
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
