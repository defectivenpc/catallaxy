# Tempo: trace ingest and query.
#
# Local storage only, for the same reason as Loki: the S3 backend is a
# consumer choice a lab with an object store makes.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "tempo";

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

        config.floe.out.component = kinds.mkComponent {
          backs.traces = [ "tempo" ];
          imagesComplete = true;

          network = {
            declared = true;
            serves.http.port = 3100;
            serves.otlpGrpc.port = 4317;
            serves.otlpHttp.port = 4318;
          };

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

            images.tempo = {
              registry = "docker.io";
              repository = "grafana/tempo";
              tag = "2.7.1";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "statefulset/tempo";
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
