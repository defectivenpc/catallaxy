# Tempo: trace ingest and query.
#
# Local storage only, for the same reason as Loki: the S3 backend is a
# consumer choice a lab with an object store makes.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "tempo";
  summary = "Tempo, the trace store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the Tempo Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "tempo";
      description = "Namespace Tempo runs in.";
    };
  };

  provides.traces = sigs.TRACE_INGEST;

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

        config.floe.out.component = kinds.mkComponent {
          backs.traces = [ "tempo" ];
          imagesComplete = true;

          bundles.tempo = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.tempo = kinds.mkHelmChart {
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

            images.tempo = kinds.mkImage "docker.io/grafana/tempo:2.7.1";

            ready = kinds.readyCondition {
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
