# OpenTelemetry Collector: one place everything in the cluster sends to.
#
# Rebuilt against RFC 0001. The parked floe was 808 lines across two files, and
# most of that was the wiring this design does not need: every backend endpoint
# was an option, set by the lab from another floe's `exports`, with an
# assertion beside it checking the lab had remembered to turn on the thing the
# endpoint pointed at.
#
# All three backends are `requiresMany`. That is not an abuse of the fan-in —
# it is what an optional dependency *is*. `requires` resolves to exactly one
# provider or fails the link; `requiresMany` resolves to however many there
# are, including none. A cluster with loki and no tempo gets a logs pipeline
# and no traces pipeline, and neither the lab nor this floe has to say so.
#
# The pipelines are built from what resolved, so a backend that is not in the
# cluster is not an exporter that is configured and failing — it is a pipeline
# that does not exist.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "otel-collector";
  summary = "An OpenTelemetry collector, exporting to whichever backends the cluster has.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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
  requiresOptional.logs = sigs.LOG_INGEST;
  requiresOptional.traces = sigs.TRACE_INGEST;
  requiresOptional.metrics = sigs.METRICS_INGEST;

  # No `provides`. The obvious one — TRACE_INGEST, so another floe can send
  # here rather than to tempo — is wrong twice over. `providersOf` includes the
  # declaring unit, so the collector would resolve its own
  # `requiresMany.traces` to itself and export into its own receiver; and
  # TRACE_INGEST carries `queryUrl`, which a collector has no answer for,
  # because it stores nothing. "Somewhere to send OTLP" and "a place traces
  # are kept and queried" are two different signatures, and the second one
  # gets designed when something needs it.

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        # Optional holes land in `floe.requires` alongside the exactly-one
        # ones, resolved to the sealed value or to `null`.
        backends =
          hole: lib.optional (config.floe.requires.${hole} or null != null) config.floe.requires.${hole};

        release = "otel-collector";

        # The chart names the Service after the release and its own name, and
        # a consumer of this floe's own OTLP endpoint needs the in-cluster
        # address rather than the one the gateway forwards to.
        gatewayHost = "${release}-opentelemetry-collector.${inputs.namespace}.svc.cluster.local";

        # ---- exporters, one per resolved backend ---------------------------
        #
        # Named `<protocol>/<signal>` rather than by the backend, because the
        # collector keys exporters by type and a second `otlphttp` would
        # silently replace the first. Indexed so two providers of the same
        # signature — two lokis, which the link permits — do not collide
        # either.

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

        # Prometheus is the odd one: it does not take OTLP. `remoteWriteUrl`
        # is on the signature for exactly this, and the exporter that speaks
        # it is a different one.
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
            # First in the list on purpose. It sheds load before anything
            # downstream allocates, which is the only order in which it
            # helps: a limiter after the batcher watches the batcher run
            # the process out of memory.
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
                # The chart's `appVersion`, not the chart version (0.156.0),
                # and not a guess — the first one here was `0.127.0` and the
                # image gate caught it. `image.tag` defaults to empty, which
                # the chart reads as appVersion, so this is what it renders.
                tag = "0.152.0";
                digest = null;
              };

              helmCharts.gateway = {
                chart = inputs.chart;
                releaseName = release;
                namespace = inputs.namespace;
                values = {
                  mode = "deployment";
                  image.repository = "otel/opentelemetry-collector-contrib";

                  ports = {
                    otlp = {
                      enabled = true;
                      # h2c, because OTLP/gRPC over a Service that does not say
                      # so gets HTTP/1.1 and the exporter never connects.
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
          # The whole attribute, not the bundle's value. `bundles.agent =
          # optionalAttrs false (mkBundle {...})` leaves an `agent` key holding
          # `{ }` — a bundle with none of its fields rather than no bundle —
          # and nothing says so until something renders it. `mkIf` is not
          # available either: `mkComponent` is a plain function, not a module.
          // lib.optionalAttrs inputs.agent {
            agent = kinds.mkBundle {
              # The agent forwards to the gateway, so the gateway's Service has
              # to exist first — not for correctness, since the exporter
              # retries, but so the first minute of a fresh cluster is not a
              # page of connection-refused in the agent's own logs.
              needs = [ "gateway" ];

              helmCharts.agent = {
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
                        # A quarter of the gateway's, because this one runs on
                        # every node and the total is what the cluster pays.
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

              # No `ready` probe. A DaemonSet has no `Available` condition to
              # wait on — that is a Deployment's — and every probe kind that
              # remains would be a hand-rolled restatement of what
              # `awaitRollout` already does. It defaults to true and waits on
              # the rollout, which for a DaemonSet asks the right question:
              # every node has the agent, not some quorum of them.
            };
          };

          assertions = [
            {
              # A collector with no backend accepts data and drops it, and
              # reports itself healthy while doing so. Nothing downstream can
              # tell that apart from a cluster nobody is sending to.
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
