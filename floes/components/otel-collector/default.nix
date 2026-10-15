# OpenTelemetry Collector: one place everything in the cluster sends to.
#
# All three backends are `optional`, which is what an optional
# dependency is: `requires` resolves to exactly one provider or fails the
# link, and this resolves to one or to nothing. A cluster with loki and no
# tempo gets a logs pipeline and no traces pipeline, and neither the lab nor
# this floe has to say so — there is no endpoint option to set and no
# assertion checking somebody remembered to turn the backend on.
#
# The pipelines are built from what resolved, so a backend that is not in the
# cluster is not an exporter that is configured and failing — it is a pipeline
# that does not exist.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "otel-collector";
  summary = "An OpenTelemetry collector, exporting to whichever backends the cluster has.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the opentelemetry-collector Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "observability";
      description = "Namespace the collector runs in.";
    };

    agent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Also run a DaemonSet that tails container logs on every node and
        forwards them to the gateway.

        Separate from the gateway because it is the expensive half: it runs
        once per node, mounts the host's log directory, and a cluster that
        already ships logs another way wants the gateway without it.
      '';
    };

    otlpGrpcPort = lib.mkOption {
      type = lib.types.port;
      default = 4317;
      description = "Port the gateway accepts OTLP/gRPC on.";
    };

    otlpHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 4318;
      description = "Port the gateway accepts OTLP/HTTP on.";
    };
  };

  # Zero or one of each, and the reason no `enable` flag or endpoint option
  # exists for any of the three. An optional hole orders like an ordinary
  # one, so the collector follows whatever backends the cluster has.
  optional.logs = sigs.LOG_INGEST;
  optional.traces = sigs.TRACE_INGEST;
  optional.metrics = sigs.METRICS_INGEST;

  # No `provides`. The obvious one — TRACE_INGEST, so another floe can send
  # here rather than to tempo — is wrong twice over. `providersOf` includes the
  # declaring unit, so the collector would resolve its own
  # `optional.traces` to itself and export into its own receiver; and
  # TRACE_INGEST carries `queryUrl`, which a collector has no answer for,
  # because it stores nothing. "Somewhere to send OTLP" and "a place traces
  # are kept and queried" are two different signatures, and the second one
  # gets designed when something needs it.

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        backends =
          hole: lib.optional (config.floe.requires.${hole} or null != null) config.floe.requires.${hole};

        release = "otel-collector";

        gatewayHost = "${release}-opentelemetry-collector.${inputs.namespace}.svc.cluster.local";

        indexed = prefix: xs: lib.imap0 (i: x: lib.nameValuePair "${prefix}/${toString i}" x) xs;

        logExporters = lib.listToAttrs (
          indexed "otlphttp" (map (l: { endpoint = l.otlpUrl; }) (backends "logs"))
        );

        traceExporters = lib.listToAttrs (
          indexed "otlp" (
            map (t: {
              endpoint = t.otlpGrpc;
              tls.insecure = true;
            }) (backends "traces")
          )
        );

        metricExporters = lib.listToAttrs (
          indexed "prometheusremotewrite" (
            map (m: {
              endpoint = m.remoteWriteUrl;
              tls.insecure = true;
            }) (backends "metrics")
          )
        );

        pipeline = exporters: receivers: {
          inherit receivers;
          processors = [
            "memory_limiter"
            "batch"
          ];
          exporters = lib.attrNames exporters;
        };

        gatewayExporters = logExporters // traceExporters // metricExporters;
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles = {
            gateway = kinds.mkBundle {
              createNamespaces = [ inputs.namespace ];

              images.collector = {
                registry = "docker.io";
                repository = "otel/opentelemetry-collector-contrib";
                tag = "0.152.0";
                digest = null;
              };

              helmCharts.gateway = kinds.mkHelmChart {
                chart = inputs.chart;
                releaseName = release;
                namespace = inputs.namespace;
                values = {
                  mode = "deployment";
                  image.repository = "otel/opentelemetry-collector-contrib";

                  ports = {
                    otlp = {
                      enabled = true;
                      appProtocol = "kubernetes.io/h2c";
                    };
                    otlp-http.enabled = true;
                  };

                  config = {
                    receivers.otlp.protocols = {
                      grpc.endpoint = "0.0.0.0:${toString inputs.otlpGrpcPort}";
                      http.endpoint = "0.0.0.0:${toString inputs.otlpHttpPort}";
                    };

                    processors = {
                      batch = {
                        timeout = "5s";
                        send_batch_size = 1000;
                      };
                      memory_limiter = {
                        check_interval = "1s";
                        limit_mib = 400;
                        spike_limit_mib = 100;
                      };
                    };

                    exporters = gatewayExporters;

                    service.pipelines =
                      lib.optionalAttrs (traceExporters != { }) {
                        traces = pipeline traceExporters [ "otlp" ];
                      }
                      // lib.optionalAttrs (metricExporters != { }) {
                        metrics = pipeline metricExporters [ "otlp" ];
                      }
                      // lib.optionalAttrs (logExporters != { }) {
                        logs = pipeline logExporters [ "otlp" ];
                      };
                  };
                };
              };

              ready = kinds.readyDeployment {
                name = "${release}-opentelemetry-collector";
                namespace = inputs.namespace;
                timeout = "3m";
              };
            };

          }
          // lib.optionalAttrs inputs.agent {
            agent = kinds.mkBundle {
              needs = [ "gateway" ];

              helmCharts.agent = kinds.mkHelmChart {
                chart = inputs.chart;
                releaseName = "${release}-agent";
                namespace = inputs.namespace;
                values = {
                  mode = "daemonset";
                  image.repository = "otel/opentelemetry-collector-contrib";

                  presets = {
                    logsCollection.enabled = true;
                    kubernetesAttributes.enabled = true;
                  };

                  config = {
                    processors = {
                      batch.timeout = "5s";
                      memory_limiter = {
                        check_interval = "1s";
                        limit_mib = 200;
                        spike_limit_mib = 50;
                      };
                    };

                    exporters.otlp = {
                      endpoint = "${gatewayHost}:${toString inputs.otlpGrpcPort}";
                      tls.insecure = true;
                    };

                    service.pipelines.logs = {
                      receivers = [ "filelog" ];
                      processors = [
                        "memory_limiter"
                        "k8sattributes"
                        "batch"
                      ];
                      exporters = [ "otlp" ];
                    };
                  };
                };
              };

            };
          };

          assertions = [
            {
              assertion = gatewayExporters != { };
              message =
                "no LOG_INGEST, TRACE_INGEST or METRICS_INGEST is provided in this cluster, so the "
                + "collector would accept telemetry and have nowhere to put it";
            }
          ];
        };
      }
    )
  ];
}
