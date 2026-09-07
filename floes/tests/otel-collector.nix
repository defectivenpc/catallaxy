# otel-collector, alone.
#
# The floe exists to test one idea: three optional backends, expressed as
# `requiresMany` rather than as three `enable` flags with three endpoint
# options and three assertions checking the lab set them consistently. So most
# of this is about what happens at each width — all three, one, none.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  evalWith =
    without:
    support.evalFloe {
      name = "otel-collector";
      inputs.chart = "/dev/null";
      inherit without;
    };

  r = evalWith [ ];

  configOf = res: res.bundles.gateway.helmCharts.gateway.values.config;
  pipelinesOf = res: lib.attrNames (configOf res).service.pipelines;
  exportersOf = res: lib.attrNames (configOf res).exporters;
in
lib.runTests {

  # ---- the fan-in, at full width ---------------------------------------

  testEveryResolvedBackendBecomesAPipeline = {
    expr = pipelinesOf r;
    expected = [
      "logs"
      "metrics"
      "traces"
    ];
  };

  # Endpoints off the signatures. The parked floe took each as an option the
  # lab set from another floe's `exports`, with an assertion beside it
  # checking the lab had turned on the thing the endpoint pointed at.
  testEndpointsComeFromTheSignatures = {
    expr = {
      logs = (configOf r).exporters."otlphttp/0".endpoint;
      traces = (configOf r).exporters."otlp/0".endpoint;
      metrics = (configOf r).exporters."prometheusremotewrite/0".endpoint;
    };
    expected = {
      logs = support.stubs.logIngest.value.otlpUrl;
      traces = support.stubs.traceIngest.value.otlpGrpc;
      metrics = support.stubs.metricsIngest.value.remoteWriteUrl;
    };
  };

  # Prometheus does not speak OTLP. `remoteWriteUrl` is on the signature for
  # exactly this, and the exporter that speaks it is a different one.
  testMetricsUseRemoteWriteRatherThanOtlp = {
    expr = lib.any (e: lib.hasPrefix "prometheusremotewrite" e) (exportersOf r);
    expected = true;
  };

  # ---- the fan-in, narrower --------------------------------------------

  # The whole point. A cluster without tempo is not a traces pipeline
  # configured against an endpoint that refuses connections — it is no traces
  # pipeline, and neither the lab nor this floe had to say so.
  testAMissingBackendIsAMissingPipeline = {
    expr = pipelinesOf (evalWith [ "traceIngest" ]);
    expected = [
      "logs"
      "metrics"
    ];
  };

  testAMissingBackendIsAlsoAMissingExporter = {
    expr = lib.any (e: lib.hasPrefix "otlp/" e) (exportersOf (evalWith [ "traceIngest" ]));
    expected = false;
  };

  testOneBackendIsEnough = {
    expr = pipelinesOf (evalWith [
      "traceIngest"
      "metricsIngest"
    ]);
    expected = [ "logs" ];
  };

  # A collector with nowhere to send accepts telemetry, drops it, and reports
  # itself healthy the whole time. Nothing downstream can tell that apart
  # from a cluster nobody is sending to.
  testNoBackendAtAllIsRefused = {
    expr = map (a: a.assertion) (
      (evalWith [
        "logIngest"
        "traceIngest"
        "metricsIngest"
      ]).component.assertions
    );
    expected = [ false ];
  };

  # ---- the two halves ---------------------------------------------------

  # The agent forwards to the gateway's Service, so the gateway has to be
  # applied first — not for correctness, since the exporter retries, but so a
  # fresh cluster's first minute is not a page of connection-refused.
  testTheAgentFollowsTheGateway = {
    expr = r.bundles.agent.needs;
    expected = [ "gateway" ];
  };

  # The expensive half: one pod per node, mounting the host's log directory.
  # A cluster already shipping logs another way wants the gateway alone.
  testTheAgentIsOptional = {
    expr =
      (support.evalFloe {
        name = "otel-collector";
        inputs = {
          chart = "/dev/null";
          agent = false;
        };
      }).bundles ? agent;
    expected = false;
  };

  # A limiter after the batcher watches the batcher run the process out of
  # memory. It only helps if it sheds load before anything downstream
  # allocates, which means first.
  testTheMemoryLimiterRunsBeforeTheBatcher = {
    expr = lib.head (configOf r).service.pipelines.logs.processors;
    expected = "memory_limiter";
  };

  # OTLP/gRPC over a Service that does not declare h2c gets HTTP/1.1, and the
  # exporter never connects.
  testTheOtlpPortDeclaresH2c = {
    expr = r.bundles.gateway.helmCharts.gateway.values.ports.otlp.appProtocol;
    expected = "kubernetes.io/h2c";
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

}
